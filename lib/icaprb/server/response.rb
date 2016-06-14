require_relative './data_structures'
require_relative './constants'
require 'date'
require 'erb'
module ICAPrb
  module Server
    # The Response class creates a valid ICAP response to send over the socket.
    class Response
      # A +Hash+ containing the header of the ICAP response
      attr_accessor :icap_header
      # The ICAP Version - usually 1.0
      attr_accessor :icap_version
      # The ICAP status code like 200 for OK
      attr_accessor :icap_status_code
      # the parts of the ICAP response
      attr_accessor :components
      # creates a new instance of ICAPrb::Server::Response and initialises some headers
      def initialize
        # the ISTag is used to let the proxy know that the old response (probably cached)
        # is invalid if this value changes
        @icap_header = {'Date' => Time.now.gmtime, 'Server' => 'ICAP.rb', 'Connection' => 'Close', 'ISTag' => '"replace"'}
        @icap_version = '1.0'
        @icap_status_code = 200
        @components = []
      end

      # creates the status line for the ICAP protocol
      # Returns the status line as a +String+
      def response_line
        "ICAP/#{@icap_version} #{@icap_status_code} #{ICAP_STATUS_CODES[@icap_status_code]}\r\n"
      end

      # convert an hash of keys (header names) and values to a +String+
      #
      # Params:
      # +value+:: the hash to convert
      #
      # Returns:: the ICAP headers as +String+
      def hash_to_header
        headers = []
        # add Encapsulated Header if we have a body
        encapsulated = encapsulated_header
        value = @icap_header
        value = @icap_header.merge(encapsulated) if encapsulated['Encapsulated'].length > 0
        value.each do |key, value|
          headers << "#{key}: #{value}"
        end
        headers.join("\r\n") + "\r\n\r\n"
      end

      # creates the encapsulated header from an array of components which it is for
      # Params:
      # +components+:: an array of the components of the ICAP response The components can be an instance of
      #                RequestHeader, RequestBody, ResponseHeader or ResponseBody
      #
      # Returns::
      # A Hash containing only one entry with the key 'Encapsulated' which holds the offsets of the components
      def encapsulated_header
        encapsulated_hdr = 'Encapsulated'
        encapsulated_hdr_list = []
        offset = 0
        @components.sort.each do |component|
          case component
            when RequestHeader
              encapsulated_hdr_list << "req-hdr=#{offset}"
            when ResponseHeader
              encapsulated_hdr_list << "res-hdr=#{offset}"
            when RequestBody
              encapsulated_hdr_list << "req-body=#{offset}"
            when ResponseBody
              encapsulated_hdr_list << "res-body=#{offset}"
            when NullBody
              encapsulated_hdr_list << "null-body=#{offset}"
          end
          offset += component.to_s.length
        end
        {encapsulated_hdr => encapsulated_hdr_list.join(', ')}
      end
      # writes the headers into a string and returns them
      # it raises an exception if the response would be incorrectly created (for example multiple headers)
      # it will create the full ICAP + HTTP header (if available)
      def write_headers
        output  = response_line
        output += hash_to_header
        s_comp = @components.sort

        # add request header if it exists
        request_header = s_comp.select {|component| component.class == RequestHeader}
        raise 'The request header can be included only once' if request_header.count > 1
        request_header.each do |rh|
          output += rh.to_s
        end

        # add response header to the response if it exists
        response_header = s_comp.select {|component| component.class == ResponseHeader}
        raise 'The request header can be included only once' if response_header.count > 1
        response_header.each do |rh|
          output += rh.to_s
        end
        # return the output
        output
      end

      # send headers to the client.
      #
      # Params:
      # +io+:: Socket where the headers should be sent to
      def write_headers_to_socket(io)
        io.write write_headers
      end
      # basic template for a HTML error page
      ERROR_TEMPLATE = ERB.new('<html><head><meta charset="utf-8" /><title>ICAP.rb<% unless params["title"].nil? %> ::'+
                                   ' <%= params["title"] %><% end %></title></head>'+
                                   '<body><h1><%= params["title"] || "Error" %></h1><div>'+
                                   '<%= params["content"] || "Content missing" %></div></body></html>')
      # display an error page when something is not ok
      # this is a server function because it is also required for errors which cannot be caught by a service
      #
      # Params
      # +io+:: The object, where the response should be written to
      # +status+:: ICAP status code to send
      # +params+:: parameters for the template and the response as well
      def self.display_error_page(io,status, params)
        response = Response.new
        response.icap_status_code = status
        http_resp_header = ResponseHeader.new(params[:http_version],params[:http_status])
        http_resp_header['Content-Type'] = 'text/html; charset=utf-8'
        http_resp_body = ResponseBody.new(ERROR_TEMPLATE.result(binding), false)
        http_resp_header['Content-Length'] = http_resp_body.length
        response.components << http_resp_header
        response.components << http_resp_body
        response.write_headers_to_socket io
        io.write(http_resp_body.to_chunk)
        send_last_chunk(io,false)
        io.close
      end

      # this method is an alternative to display_error_page. It does not send any http information to the client.
      # instead it will send an ICAP header which will indicate an error.
      def self.error_response(io)
        response = Response.new
        response.icap_status_code = 500
        response.components << NullBody.new
        response.write_headers_to_socket io
      end

      # sends the information to the client, that it should send the rest of the file. This method does not keep
      # track of your connection and if you call it twice, your client may have trouble with your response. Use
      # it only once and only in +preview+ mode.
      def self.continue(io,icap_version = '1.0')
        io.write "ICAP/#{icap_version} 100 Continue\r\n\r\n"
      end

      # this method sends the last (empty) chunk and it will add the ieof marker if it is requested.
      # this empty chunk is used to indicate the end of the body encoded in chunked encondig.
      def self.send_last_chunk(io,in_preview = false)
        data = '0'
        if in_preview
          data += '; ieof'
        end
        data += "\r\n\r\n"
        io.write(data)
      end

    end
  end
end

