require 'spec_helper'

describe ICAPrb::Server::Response do

  it 'creates a correct request line' do
    resp = ICAPrb::Server::Response.new
    resp.icap_status_code = 200
    expect(resp.response_line).to eq "ICAP/1.0 200 OK\r\n"
    resp.icap_status_code = 451
    resp.icap_version = '1.1'
    expect(resp.response_line).to eq "ICAP/1.1 451 Unavailable For Legal Reasons\r\n"
  end

  it 'converts an header array to a string correctly' do
    resp = ICAPrb::Server::Response.new
    resp.icap_header = {'Server' => 'ICAP.rb', 'Connection' => 'Close'}
    expect(resp.hash_to_header).
        to eq("Server: ICAP.rb\r\nConnection: Close\r\n\r\n")
  end

  it 'creates an correct ICAP Header which answers the request' do
    resp = ICAPrb::Server::Response.new
    resp.icap_header = {'Server' => 'ICAP.rb', 'Connection' => 'Close'}
    http_response = ICAPrb::Server::ResponseHeader.new('1.1', 204)
    http_response['Server'] = 'blank page server'
    http_response['Content-Length'] = '0'
    body = ICAPrb::Server::NullBody.new
    resp.components << http_response
    resp.components << body

    expect(resp.write_headers).
      to eq("ICAP/1.0 200 OK\r\n" +
            "Server: ICAP.rb\r\n" +
            "Connection: Close\r\n" +
            "Encapsulated: res-hdr=0, null-body=73\r\n\r\n" +
            # http
            "HTTP/1.1 204 No Content\r\n" +
            "Server: blank page server\r\n" +
            "Content-Length: 0\r\n\r\n"
         )
  end

end