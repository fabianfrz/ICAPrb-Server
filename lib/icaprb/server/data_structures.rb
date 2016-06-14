# patch ruby strings
class String
  # converts the string to a chunk (chunked encoding)
  def to_chunk
    length.to_s(16) + "\r\n" + self + "\r\n"
  end
  # extracts a ruby string from a chunk (chunked encoding)
  def chunk_to_s
    len_alpha = scan(/\A([\da-fA-F]+)\r\n/).first.first
    len = len_alpha.to_i(16)
    offset_data = len_alpha.length + 2 # 2 = CRLF
    end_of_message = (offset_data+len)
    str = self[offset_data...end_of_message]
    raise 'Too many data in chunk' if end_of_message + 2 != length
    str
  end
end

module ICAPrb
  module Server

    # This class is the base for the HTTP header classes. It is a subclass of +Hash+.
    class HTTP_Header < Hash

      # Converts the array to a +String+ and which will be the complete HTTP Header,
      # witch contains the request or status line.
      #
      # It will join the headers with \r\n and ends with \r\n\r\n
      def to_s
        data = []
        each do |key, value|
          data << "#{key}: #{value}"
        end
        request_line + data.join("\r\n") + "\r\n\r\n"
      end
    end

    # The +RequestHeader+ represents the header information of an HTTP request. It contains the status line as well as
    # the other headers. The headers are accessible by the array access operator
    class RequestHeader < HTTP_Header
      # the path requested by the user
      attr_accessor :http_path
      # The HTTP Method (also known as Verb) as a String. For Example GET, POST, PUT, DELETE or OPTIONS
      attr_accessor :http_method
      # The HTTP version which is used by the application
      attr_accessor :http_version

      # Initializes a new Object of +RequestHeader+
      # Params:
      # +http_method+:: The HTTP Method (also known as Verb) as a String. For Example GET, POST, PUT, DELETE or OPTIONS
      # +http_path+:: The Resource which has been requested by the user
      # +http_version+:: The HTTP version which is used by the application
      def initialize(http_method, http_path, http_version = '1.1')
        @http_method = http_method
        @http_path = http_path
        @http_version = http_version
      end

      # The request header is always the first header and it can be included only once in an ICAP response
      def <=>(value)
        return 0 if value.class == RequestHeader
        -1
      end

      # creates the request line for the request
      # it will include the method, the path and the used http version.
      def request_line
        "#{@http_method} #{@http_path} HTTP/#{@http_version}\r\n"
      end
    end

    # This class represents the +Body+ of an HTTP request. It has to come after the headers in ICAP messages.
    # It will be used if the request contains data (usually POST)
    #
    # Use the << operator to concatenate the strings as + would return a string and your ICAP answer would fail.
    class RequestBody < String
      # true if we are in the preview
      attr_accessor :ieof

      # initializes a new RequestBody which is a String but has an ieof tag additionally.
      def initialize (string, ieof = false)
        super string
        @ieof = ieof
      end
      # A body comes after the headers
      def <=>(other)
        case other
          when RequestHeader
            1
          when ResponseHeader
            1
          when RequestBody
            0
          when ResponseBody
            0
          when NullBody
            -1
        end
      end

    end

    # This class represents the +Header+ of an HTTP response. It includes the headers sent by the web server as well as
    # the status line
    class ResponseHeader < HTTP_Header
      # Params:
      # +http_version+:: is the version of http to use - usually 1.1
      # +status_code+:: is the status code of the http protocol. For example 200 for OK
      def initialize(http_version, status_code)
        @http_version = http_version
        @status_code = status_code
      end

      # creates the response line for the request
      # it will contain the http version, the status code and the status text from HTTP_STATUS_CODES
      def request_line
        "HTTP/#{@http_version} #{@status_code} #{HTTP_STATUS_CODES[@status_code]}\r\n"
      end

      # The request header has to come first
      def <=>(other)
        case other
          when RequestHeader
            1
          when ResponseHeader
            0
          else
            -1
        end
      end
    end

    # This class represents the response body which should be sent to the user.
    # If it is missing, it could be replaced by a NullBody
    class ResponseBody < String
      # if it is in the preview, this will be true, otherwise nil or false
      attr_accessor :ieof

      # initializes a new RequestBody which is a String but has an ieof tag additionally.
      def initialize(string, ieof = false)
        super string
        @ieof = ieof
      end

      # compare to sort within an array
      # Response Bodies are usually at the end
      def <=>(other)
        case other
          when RequestHeader
            1
          when ResponseHeader
            1
          when RequestBody
            0
          when ResponseBody
            0
          when NullBody
            -1
        end
      end
    end

    # The +NullBody+ is a Class to have an Body without content. It exists to let the ICAP client know, that there
    # will not be any body for this HTTP request. This usually happens when a 204 No Content ist sent.
    class NullBody
      # Returns an empty +String+
      def to_s
        ''
      end

      # It is always the last entry in ICAP responses.
      def <=>(_)
        1
      end

      # Show an empty string on the IRB instead of the object id, so it looks like a +ResponseBody+
      def inspect
        '""'
      end
    end
  end
end