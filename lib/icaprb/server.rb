require 'icaprb/server/version'
require 'openssl'
require 'socket'
require 'logger'

require_relative './server/request_parser'
require_relative './server/response'
require_relative './server/services'
# nodoc
module ICAPrb
  # The server code of our project.
  module Server
    # This class contains the network related stuff like waiting for connections.
    # It is the main class of this project.
    class ICAPServer
      # supported ICAP versions
      SUPPORTED_ICAP_VERSIONS = ['1.0']
      # logger for the server; default level is Logger::WARN and it writes to STDOUT
      attr_accessor :logger
      # services registered on the server
      attr_accessor :services

      # Create a new ICAP server
      #
      # * <b>host</b> the host on which the socket should be bound to
      # * <b>port</b> the port on which the socket should be bound to - this is usually 1344
      # * <b>options</b> when you want to use TLS, you can pass a Hash containing the following information
      #   :secure:: true if TLS should be used
      #   :certificate:: the path of the certificate
      #   :key:: the path of the key file
      def initialize(host = 'localhost', port = 1344, options = nil)
        @host, @port = host,port
        @secure = false
        @certificate = nil
        @key = nil
        if (options.is_a? Hash) && (@secure = options[:secure])
          @key = options[:key]
          @certificate = options[:certificate]
        end

        if (options.is_a? Hash) && options[:logfile]
          @logger = Logger.new(options[:logfile])
        else
          @logger = Logger.new(STDOUT)
        end

        if (options.is_a? Hash) && options[:log_level]
          @logger.level = options[:log_level]
        else
          @logger.level = Logger::WARN
        end

        @services = {}

        @enable_tls_1_1 = options[:enable_tls_1_1] unless options.nil?

        @tls_socket = false
        if (options.is_a? Hash) && options[:tls_socket]
          @tls_socket = options[:tls_socket]
        end
      end

      # this methods starts the server and passes the connection to the method handle_request
      # as well as the ip and the port.
      # It will log the information about the connection if the level is set to info or lower.
      #
      # this method will most likely never crash. It is blocking so you may want to run it in
      # its own thread.
      def run
        # run the server
        server = create_server
        loop do

          Thread.start(server.accept) do |connection|

            if connection.is_a? OpenSSL::SSL::SSLSocket
              port, ip = Socket.unpack_sockaddr_in(connection.io.getpeername)
            else
              port, ip = Socket.unpack_sockaddr_in(connection.getpeername)
            end
            @logger.info "[CONNECT] Client from #{ip}:#{port} connected to this server"
            begin
              until connection.closed? do
                handle_request(connection,ip)
              end
            rescue Errno::ECONNRESET => e
              @logger.error "[CONNECTION ERROR] Client #{ip}:#{port} got disconnected (CONNECTION RESET BY PEER): #{e}"
            end
          end

        end
      end

      # this method handles the connection to the client. It will call the parser and sends the request to the service.
      # The service must return anything and handle the request. The important classes are in response.rb
      # This method includes a lot of error handling. It will respond with an error page if
      # * The ICAP version is not supported
      # * It cannot read the header
      # * The method is not supported by the service
      # * The request has an upgrade header, which is not supported
      # * the client requested an upgrade to tls, but the server has not been configured to use it
      # * the client requested a service, which does not exist
      def handle_request(connection, ip)
        # handles the request
        begin
          parser = RequestParser.new(connection, ip, self)
          parsed_data = parser.parse
        rescue Exception => e
          #puts $@
          logger.error "[PARSER ERROR] Error while parsing request - Error Message is: #{e}"
          Response.display_error_page(connection,400,
                                      {http_version: '1.0',http_status: 400, 'title' => 'Invalid Request',
                                       'content' => 'Your client sent a malformed request - please fix it and try it again.'})
          return
        end

        unless SUPPORTED_ICAP_VERSIONS.include? parsed_data[:icap_data][:request_line][:version]
          Response.display_error_page(connection,505,
                                      {http_version: '1.0',
                                       http_status: 500,
                                       'title' => 'Unknown ICAP-version used',
                                       'content' => 'We are sorry but your ICAP version is not known by this server.'})
        end

        # send the data to the service framework
        path = parsed_data[:icap_data][:request_line][:uri].path
        path = path[1...path.length] if path != '*'
        if (service = @services[path])
          icap_method = parsed_data[:icap_data][:request_line][:icap_method]
          if icap_method == :options
            return service.generate_options_response(connection)
          else
            if service.supported_methods.include? icap_method
              service.do_process(self,ip,connection,parsed_data)
              return
            else
              Response.display_error_page(connection,405,
                                          {http_version: '1.0',http_status: 500, 'title' => 'ICAP Error',
                                           'content' => 'Your client accessed the service with the wrong method.'})
            end
          end

        elsif (path == '*') &&  (parsed_data[:icap_data][:request_line][:icap_method] == :options)
          # check for an upgrade header
          icap_data = parsed_data[:icap_data]
          if icap_data[:header]['Connection'] == 'Upgrade' && connection.class == OpenSSL::SSL::SSLSocket
            case icap_data[:header]['Upgrade']
              when /^TLS\/[\d\.]+, ICAP\/[\d\.]+$/
                response = Response.new
                response.icap_status_code = 101
                response.icap_header['Upgrade'] = "TLS/1.2, ICAP/#{icap_data[:request_line][:version]}"
                response.write_headers_to_socket connection
                connection.accept # upgrade connection to use tls
              else
                Response.display_error_page(connection,400,{'title' => 'ICAP Error',
                                                            'content' => 'Upgrade header is missing',
                                                            :http_version => '1.1',
                                                            :http_status => 500})
            end
          else
            Response.display_error_page(connection,500,{'title' => 'ICAP Error',
                                                        'content' => 'This server has no TLS support.',
                                                        :http_version => '1.1',
                                                        :http_status => 500})
          end
          return
        else
          Response.display_error_page(connection,404,
                                      {http_version: '1.0',http_status: 500, 'title' => 'Not Found',
                                       'content' => 'Sorry, but the ICAP service does not exist.'})
          return
        end

      end

      private
      # this method will create a server based on the information we got on initialisation.
      # It will create an +TCPServer+ with the host and port given at initialisation.
      # If @secure evaluates to true, a +SSLServer+ will be crated and wraps this +TCPServer+.
      # By default, only TLS 1.2 is supported for security reasons but TLS 1.1 can be enabled
      # as well when the option is set at initialization.
      # For security reasons, the encryption algorithms +RC4+ and +DES+ are disabled as well as the
      # digest algorithm +SHA1+.
      # returns: An instance of TCPServer or SSLServer
      def create_server
        tcp_server = TCPServer.new(@host, @port)
        if @secure
          ctx = OpenSSL::SSL::SSLContext.new(:TLSv1_2_server)
          ctx.cert = OpenSSL::X509::Certificate.new(File.read(@certificate))
          ctx.key  = OpenSSL::PKey::RSA.new(File.read(@key))
          # secure OpenSSL
          ###############################
          # do not allow ssl v2 or ssl v3
          ctx.options |= (OpenSSL::SSL::OP_NO_SSLv2 | OpenSSL::SSL::OP_NO_SSLv3 | OpenSSL::SSL::OP_NO_TLSv1)
          # disable TLS 1.1 unless the user requests it
          ctx.options |= OpenSSL::SSL::OP_NO_TLSv1_1 unless @enable_tls_1_1

          # I do not want to have something encrypted with RC4 or with a DES variant and it should not use the digest
          # algorithm SHA1
          ctx.ciphers =
            OpenSSL::SSL::SSLContext::DEFAULT_PARAMS[:ciphers].split(':').select do |cipher_suite|
              !((cipher_suite =~ /RC4|DES/) || (cipher_suite =~ /SHA$/))
            end.join(':')
          tcp_server = OpenSSL::SSL::SSLServer.new(tcp_server, ctx)
          tcp_server.start_immediately = @tls_socket # requires accept call later
        end
        @tcp_server = tcp_server
      end
    end
  end
end
