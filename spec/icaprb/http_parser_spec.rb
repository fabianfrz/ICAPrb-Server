require 'spec_helper'
require 'stringio'

describe ICAPrb::Server::HTTPHeaderParser do
  it 'parses the request line correctly' do
    http_header = ICAPrb::Server::HTTPHeaderParser.new(nil)
    test1 = 'GET / HTTP/1.0'
    test2 = 'POST /test.php?test=test HTTP/1.1'
    test3 = 'REQMOD icap://localhost/echo ICAP/1.0'

    parsed1 = http_header.parse_http_request_line(test1)
    parsed2 = http_header.parse_http_request_line(test2)

    expect(parsed1[:http_method]).to eq 'GET'
    expect(parsed2[:http_method]).to eq 'POST'

    expect(parsed1[:uri].to_s).to eq '/'
    expect(parsed2[:uri].to_s).to eq '/test.php?test=test'

    expect(parsed1[:version]).to eq '1.0'
    expect(parsed2[:version]).to eq '1.1'

    expect {http_header.parse_http_request_line(test3)}.to raise_error(ICAPrb::Server::Parser::HTTP_Parse_Error)
  end

  it 'raises an exception if the request line is wrong' do
    http_header = ICAPrb::Server::HTTPHeaderParser.new(nil)
    test1 = 'TEST /test.php?test=test HTTP/1.1'
    test2 = 'POST /test.php?test=test TEST/1.1'

    expect {http_header.parse_http_request_line(test1)}.to raise_error(ICAPrb::Server::Parser::HTTP_Parse_Error)
    expect {http_header.parse_http_request_line(test2)}.to raise_error(ICAPrb::Server::Parser::HTTP_Parse_Error)
  end



  it 'parses the response line correctly' do
    http_header = ICAPrb::Server::HTTPHeaderParser.new(nil)
    test1 = "HTTP/1.0 200 OK\r\n"
    test2 = "HTTP/1.1 404 NOT FOUND\r\n"
    test3 = 'TEST'

    parsed1 = http_header.parse_http_response_line(test1)
    parsed2 = http_header.parse_http_response_line(test2)

    expect(parsed1[:code]).to eq 200
    expect(parsed2[:code]).to eq 404

    expect(parsed1[:version]).to eq '1.0'
    expect(parsed2[:version]).to eq '1.1'

    expect {http_header.parse_http_request_line(test3)}.to raise_error(ICAPrb::Server::Parser::HTTP_Parse_Error)
  end

  it 'raises an exception if the response line is wrong' do
    http_header = ICAPrb::Server::HTTPHeaderParser.new(nil)
    test1 = "ICAP/1.0 200 OK\r\n"
    test2 = "HTTP/1.1 600 DOES NOT EXIST\r\n"

    expect {http_header.parse_http_response_line(test1)}.to raise_error(ICAPrb::Server::Parser::HTTP_Parse_Error)
    # the status code does not exist but it has a valid format
    expect {http_header.parse_http_response_line(test2)}.not_to raise_error
  end
end