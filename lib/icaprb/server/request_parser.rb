require 'uri'
module ICAPrb
  module Server
    # The Parser module contains methods to parse ICAP or HTTP messages.
    module Parser

      # This class indicates an error while parsing the request
      class ICAP_Parse_Error < RuntimeError
      end
      # This class indicates an error while parsing the request
      class HTTP_Parse_Error < RuntimeError
      end

      # This module contains the Methods included in the request parser as well as in the Service.
      # It is used to provide parsing methods which are used to read the full request.
      module ChunkedEncodingHelper
        # this method reads a chunk from an Object, which supports the method "gets" and it is usually a socket.
        # it will return the data sent over the socket and return it. It will also return the information,
        # if the chunk had an ieof flag set. ieof means there is no data available and the server must not ask
        # to continue.
        #
        # params:
        # +io+:: socket
        #
        # returns:
        # [string data, ieof_set]
        private
        def read_chunk(io)
          str = "\r\n"
          until (str = io.gets) != "\r\n"
          end
          total_length, ieof = read_chunk_length(str)
          result = ''
          until result.length >= total_length
            result += io.gets
          end
          if total_length == 0
            return :eof,ieof
          end
          # cut the protocol overhead
          return result[0...total_length], ieof
        end

        # returns the length of the chunk as first argument and if ieof is set as second
        private
        def read_chunk_length(line)
          x = line.scan(/\A([A-Fa-f0-9]+)(; ieof)?\r\n/).first
          [x[0].to_i(16), !x[1].nil?]
        end
      end

      # parse header line and returns the parsed line as Array which has the name on index 0 and the value on index 1
      def parse_header(line)
        # remove newlines
        line = line.gsub!("\r",'')
        line = line.gsub!("\n",'')
        line.split(':',2).map {|x| x.strip}
      end


    end
    # This class is used to parse ICAP requests. It includes the Parser module.
    class ICAPRequestParser
      include Parser

      # initializes a new ICAP request parser
      # params:
      # +io+:: the Socket
      def initialize(io)
        @io = io
      end

      # This method parses the request line and returns an Hash with the components
      # * icap_method:: can be :req_mod, :resp_mod or :options
      # * uri:: an URI
      # * version:: the used version of ICAP
      # @raise ICAP_Parse_Error if something is invalid
      def parse_icap_request_line(line)
        str_method, str_uri,_,_,_, str_version = line.scan(/(REQMOD|RESPMOD|OPTIONS) (((icap[s]?:)?[^\s]+)|(\*)) ICAP\/([\d\.]+)/i).first
        raise ICAP_Parse_Error.new "invalid icap Method in RequestLine #{line}" if str_method.nil?
        case str_method.upcase
          when 'REQMOD'
            icap_method = :request_mod
          when 'RESPMOD'
            icap_method = :response_mod
          when 'OPTIONS'
            icap_method = :options
          else
            raise ICAP_Parse_Error.new 'The request type is not known'
        end
        uri = URI(str_uri)
        unless icap_method && uri && str_version
          raise ICAP_Parse_Error.new 'The request line is not complete.'
        end
        {icap_method: icap_method, uri: uri, version: str_version}
      end

      # parse all headers
      def parse
        line = "\r\n"
        while line == "\r\n"
          line = @io.gets
        end
        return nil unless line
        icap_req_line = parse_icap_request_line(line)
        icap_headers = {}
        until (line = @io.gets) == "\r\n"
          parsed_header = parse_header(line)
          icap_headers[parsed_header[0]] = parsed_header[1]
        end
        {request_line: icap_req_line, header: icap_headers}
      end
    end

    # parses HTTP Headers
    class HTTPHeaderParser
      include Parser

      # initializes a new HTTPHeaderParser
      # params:
      # +io+:: the socket
      # +is_request+:: value to say if it is an response or an request because the request line / status line
      #                look different
      def initialize(io,is_request = true)
        @io = io
        @length_read = 0
        @is_request = is_request
      end
      # This method parses the request line and returns an Hash with the components
      # * http_method:: a string
      # * uri:: an URI
      # * version:: the used version of HTTP
      # @raise HTTP_Parse_Error if something is invalid
      def parse_http_request_line(line)
        @length_read += line.length
        str_method, str_uri, str_version = line.scan(/(GET|POST|PUT|DELETE|PATCH|OPTIONS|TRACE|HEAD|CONNECT) (\S+) HTTP\/([\d\.]+)/i).first
        raise HTTP_Parse_Error.new 'invalid http Method' if str_method.nil?
        uri = URI(str_uri)
        unless str_method && uri && str_version
          raise HTTP_Parse_Error.new 'The request line is not complete.'
        end
        {http_method: str_method, uri: uri, version: str_version}
      end
      # This method parses the response line and returns an Hash with the components
      # * status:: an integer
      # * version:: the used version of HTTP
      # @raise HTTP_Parse_Error if something is invalid
      def parse_http_response_line(line)
        @length_read += line.length
        str_version, str_code, _ = line.scan(/HTTP\/([\d\.]+) (\d+) ([A-Za-z0-9 \-]+)\r\n/i).first
        raise HTTP_Parse_Error.new 'invalid Code' if str_code.nil?
        code = str_code.to_i
        unless code && str_version
          raise HTTP_Parse_Error.new 'The request line is not complete.'
        end
        {code: code, version: str_version}
      end

      # parse all headers
      def parse
        if @is_request
          http_req_line = parse_http_request_line(@io.gets)
          header = RequestHeader.new(http_req_line[:http_method],http_req_line[:uri],http_req_line[:version])
        else
          http_response_line = parse_http_response_line(@io.gets)
          header = ResponseHeader.new(http_response_line[:version],http_response_line[:code])
        end
        until (line = @io.gets) == "\r\n"
          parsed_header = parse_header(line)
          header[parsed_header[0]] = parsed_header[1]
        end
        header
      end
    end

    # The request parser uses the ICAP and HTTP parsers to parse the complete request.
    # It is the main parser used by the server which gets the socket to read the +ICAP+
    # headers which are sent by the client.
    # Depending on the headers and the values we got, we will decide, which other parsers
    # we need and how to read it. the parsed request will be returned and depending on the
    # data, the server will decide what it will do with the request.
    class RequestParser

      # create a new instance of a +RequestParser+
      # params:
      # +io+:: a socket to communicate
      # +ip+:: the peer ip address
      # +server+:: the instance of the server which uses the parser to get the service names.
      def initialize(io,ip,server)
        @io = io
        @ip = ip
        @server = server
      end

      # Parses the complete request and returns the parsed result.
      # It will return the parsed result.
      #
      # if an +Encapsulated+ header is set, it will also parse the encapsulated +HTTP+ header and the body if
      # available
      def parse
        # parse ICAP headers
        icap_parser = ICAPRequestParser.new(@io)
        icap_data = icap_parser.parse
        return nil unless icap_data
        if icap_data[:header]['Encapsulated']
          encapsulation = icap_data[:header]['Encapsulated']
          encapsulated_parts = encapsulation.split(',').map do |part|
            part.split('=').map(&:strip)
          end
        else
          encapsulated_parts = []
        end
        parsed_data = {icap_data: icap_data, encapsulated: encapsulated_parts}
        parts = []
        service_name = icap_data[:request_line][:uri].path
        service_name = service_name[1...service_name.length]
        service = @server.services[service_name]
        if service
          disable_preview = !service.supports_preview?
          preview_size = service.preview_size
        else
          disable_preview = true
          preview_size = nil
        end
        encapsulated_parts.each do |ep|
          parts << case ep[0]
            when 'null-body'
              NullBody.new
            when 'req-hdr'
              http_parser = HTTPHeaderParser.new(@io,true)
              parsed_data[:http_request_header] = http_parser.parse
            when 'res-hdr'
              http_parser = HTTPHeaderParser.new(@io,false)
              parsed_data[:http_response_header] = http_parser.parse
            when 'req-body'
              bp = BodyParser.new(@io, disable_preview, (icap_data[:header]['Preview'] || nil))
              p_data = bp.parse
              parsed_data[:http_request_body] = RequestBody.new(p_data[0],p_data[1])
            when 'res-body'
              bp = BodyParser.new(@io, disable_preview, (icap_data[:header]['Preview'] || nil))
              p_data = bp.parse
              parsed_data[:http_response_body] = ResponseBody.new(p_data[0],p_data[1])
            else
              nil
          end
        end

        parsed_data
      end
    end

    # this class will parse an http body which has to be chunked encoded.
    class BodyParser
      # By default, it will try to receive all data if the service does not provide information,
      # if it supports previews.
      # params:
      # +io+:: the Socket
      # +read_everything+:: read all data before forwarding them to the service - true by default
      #                     (set a preview size in the service to override)
      # +preview_header+:: if a preview header is set, we can find out how long the preview will be.
      #                    so we know how much data we can expect.
      def initialize(io, read_everything = true, preview_header = nil)
        @io = io
        @read_everything = read_everything
        if preview_header
          @preview_size = preview_header.to_i
        else
          @preview_size = nil
        end
      end

      # parses all chunks and concatenates then until:
      # * the end of the preview is reached and the service is not correctly configured
      # * die end of the data is reached
      # it will return the data it got and if the ieof has been set.
      def parse
        data = ''
        ieof = false
        until (line,ieof = read_chunk(@io); line) && line == :eof
          data += line
        end
        if !ieof && @read_everything && !@preview_size.nil? && (@preview_size >= data.length)
          Response.continue(@io)
          until (line,ieof2 = read_chunk(@io); line) && line == :eof
            data += line
            ieof ||= ieof2
          end
        end
        return data, ieof
      end

      include ::ICAPrb::Server::Parser::ChunkedEncodingHelper
    end
  end
end