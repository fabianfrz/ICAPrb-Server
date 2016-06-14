require 'timeout'
module ICAPrb
  module Server
    # this module contains the code, which is required to build an ICAP service
    module Services
      # Base class for ICAP services
      class ServiceBase
        # the name of the service which is used in the response header (Service-Name)
        attr_accessor :service_name
        # send the ttl via options header - the options are valid for the given time
        attr_accessor :options_ttl
        # the supported methods for this service. This must be an +Array+ which contains symbols.
        # The values are:
        #
        # :request_mod:: request mod is supported
        # :response_mod:: response mod is supported
        #
        # Do not add :options - this would be wrong here!
        attr_accessor :supported_methods
        # The preview size has to be set if the server supports previews. Otherwise use +nil+ here.
        # If your service supports previews
        attr_accessor :preview_size
        # +Array+ of file extensions which should be always sent to the +ICAP+ server (no preview)
        attr_accessor :transfer_complete
        # +Array+ of file extensions which should not be sent to the +ICAP+ server (not even a preview)
        attr_accessor :transfer_ignore
        # +Array+ of file extensions which need a preview sent to the +ICAP+ server
        # (do not send the full file in advance)
        attr_accessor :transfer_preview
        # Maximum amount of concurrent connections per IP. The server will not accept more connections and answers with
        # an error
        attr_accessor :max_connections
        # The IS-Tag is a required header. If you change it, the cache of the proxy will be flushed.
        # You usually do not need to change this header. You may want to add your service name here.
        attr_accessor :is_tag
        # If you want to send a service id header to the +ICAP+ client, you can set it here. Use nil to disable
        # this header.
        attr_accessor :service_id
        # the counter is used to determine if too many connections are opened by the proxy.
        # If this is the case, the the server answers with an error
        attr_reader :counter
        # timeout for the service
        attr_accessor :timeout

        # initialize a new service
        def initialize(service_name,supported_methods  = [], preview_size = nil, options_ttl = 60,
                       transfer_preview = nil, transfer_ignore = nil, transfer_complete = nil, max_connections = 100000)  #TODO Work in progress; sort
          @service_name = service_name
          @options_ttl = options_ttl
          @supported_methods = supported_methods
          @preview_size = preview_size

          @transfer_preview = transfer_preview
          @transfer_ignore = transfer_ignore
          @transfer_complete = transfer_complete
          @max_connections = max_connections
          @is_tag = nil
          @service_id = nil
          @timeout = nil

          @counter = {}
        end

        # parameters:
        # server:: reference to the icap server
        # ip:: ip address of the peer
        # socket:: socket to communicate
        # data:: the parsed request
        def process_request(_,_,_,_)
          raise :not_implemented
        end

        # returns if this service supports previews which means it can request the rest of the data if they are
        # required. If you do not override this method, this will return false so you will get the complete request.
        def supports_preview?
          return false if @preview_size.nil?
          return  preview_size >= 0
        end

        # include the ChunkedEncodingHelper for previews
        include ::ICAPrb::Server::Parser::ChunkedEncodingHelper

        # returns true if we already got all data or if we are in a preview.
        # if we are not in a preview, the preview header is not present => outside of a preview
        # and if the ieof is set, there is no data left - we have all data
        # everything else means there is data left to request.
        # NOTE: this will only work once! Do not request data after calling this method and call it again -
        # you will get a false negative.
        def got_all_data?(data)
          return true unless data[:icap_data][:header]['Preview']
          return true if data[:http_response_body].ieof
          return false
        end

        # When we get a preview, we can answer it or request the rest of the data.
        # This method will send the status "100 Continue" to request the rest of the data and
        # it will then request all the data which is left and returns this data as a single string.
        #
        # You may want to concatenate it with the data you already got in the preview using the << operator.
        #
        # WARNING: DO NOT CALL THIS METHOD IF YOU ARE NOT IN A PREVIEW!
        def get_the_rest_of_the_data(io)
          data = ''
          Response.continue(io)
          until (line,_ = read_chunk(io); line) && line == :eof
            data += line
          end
          return data
        end

        # this method is called by the server when it receives a new ICAP request
        # it will increase the counter by one, call process_request and decreases the counter by one.
        def do_process(server,ip,io,data)
          begin
            enter(ip)
          rescue
            Response.display_error_page(io,503,{'title' => 'ICAP Error',
                                                        'content' => 'Sorry, too much work for me',
                                                        :http_version => '1.1',
                                                        :http_status => 500})
            return
          end

          begin
            unless @supported_methods.include? data[:icap_data][:request_line][:icap_method]
              Response.display_error_page(io,501,{'title' => 'Method not implemented',
                                                          'content' => 'I do not know what to do with that...',
                                                          :http_version => '1.1',
                                                          :http_status => 500})
              return
            end
            if @timeout
              begin
                Timeout::timeout(@timeout) do
                  process_request(server,ip,io,data)
                end
              rescue Timeout::Error => e
                # do not do a graceful shutdown of the connection as the client may fail
                server.logger.error e
                io.close
              end
            else
              process_request(server,ip,io,data)
            end
          rescue
            leave(ip)
            raise
          end
          leave(ip)
        end

        # when the connection enters this method will increase the counter. If the counter exceeds the limit,
        # the request will be rejected
        def enter(ip)
          if @counter[ip]
            raise :connection_limit_exceeded unless (@counter[ip] < @max_connections) || @max_connections.nil?
            @counter[ip] += 1
          else
            @counter[ip] = 1
          end
        end

        # when the request is answered we can allow the next one by decrementing the counter
        def leave(ip)
          @counter[ip] -= 1
        end

        # This method is called by the server when the client sends an options request which is not a
        # mandatory upgrade.
        #
        # The data used here is set by the constructor and it should be configured when the Service
        # is initialized.
        #
        # Parameters:
        # +io+ the socket used to answer the request
        def generate_options_response(io)
          response = ::ICAPrb::Server::Response.new
          response.components << ::ICAPrb::Server::NullBody.new
          methods = []
          methods << 'REQMOD' if @supported_methods.include? :request_mod
          methods << 'RESPMOD' if @supported_methods.include? :response_mod
          response.icap_header['Methods'] = methods.join(', ')
          set_generic_icap_headers(response.icap_header)
          response.icap_header['Max-Connections'] = @max_connections if @max_connections
          response.icap_header['Options-TTL'] = @options_ttl if @options_ttl
          response.icap_header['Preview'] = @preview_size if @preview_size
          response.icap_header['Transfer-Ignore'] = @transfer_ignore.join(', ') if @transfer_ignore
          response.icap_header['Transfer-Complete'] = @transfer_complete.join(', ') if @transfer_complete
          response.icap_header['Transfer-Preview'] = @transfer_preview.join(', ') if @transfer_preview
          response.icap_header['Allow'] = '204'
          response.write_headers_to_socket io
        end

        # set headers independently from the response type
        #
        # parameters:
        # +icap_header+:: The hash which holds the ICAP headers.
        def set_generic_icap_headers(icap_header)
          icap_header['Service-Name'] = @service_name
          icap_header['ISTag'] = @is_tag if @is_tag
          icap_header['Service-ID'] = @service_id if @service_id
        end
      end

      # Sample Service to test the server
      # it will echo the complete request to the client
      class EchoService < ServiceBase
        # initializes the EchoService - the name of the echo service is echo
        def initialize
          super('echo',[:request_mod, :response_mod],1024,60,nil,nil,nil,1000)
          @timeout = nil
        end

        # return the request to the client
        def process_request(icap_server,ip,socket,data)
          logger = icap_server.logger
          logger.debug 'Start processing data via echo service...'
          response = ::ICAPrb::Server::Response.new
          response.icap_status_code = 200
          if data[:icap_data][:request_line][:icap_method] == :response_mod
            http_resp_header = data[:http_response_header]
            http_resp_body = data[:http_response_body]
          else
            http_resp_header = data[:http_request_header]
            http_resp_body = data[:http_request_body]
          end

          http_resp_body << get_the_rest_of_the_data(socket) if http_resp_body && !(got_all_data? data)
          response.components << http_resp_header
          response.components << http_resp_body
          response.write_headers_to_socket socket
          if http_resp_body.instance_of? ResponseBody
            socket.write(http_resp_body.to_chunk)
            ::ICAPrb::Server::Response.send_last_chunk(socket,false)
          end
          logger.debug 'Answered request in echo service'
        end
      end
    end
  end
end