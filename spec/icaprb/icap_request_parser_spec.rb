require 'spec_helper'
require 'stringio'

describe ICAPrb::Server::Parser do
  it 'parses a header correctly' do
    x = Object.new
    x.extend(ICAPrb::Server::Parser)
    parsed = x.parse_header("Content-Type: text/html; encoding=utf-8\r\n")
    expect(parsed[0]).to eq('Content-Type')
    expect(parsed[1]).to eq('text/html; encoding=utf-8')
  end
end

describe ICAPrb::Server::Parser::ChunkedEncodingHelper do
  it 'parses a chunk correctly' do
    x = Object.new
    x.extend(ICAPrb::Server::Parser::ChunkedEncodingHelper)

    data = StringIO.new("4\r\nTEST\r\n0\r\n\r\n")
    data.rewind
    s, ieof = x.send(:read_chunk,data)
    expect(s).to eq('TEST')
    expect(ieof).to be_falsey

    data = StringIO.new("0; ieof\r\n\r\n")
    data.rewind
    s, ieof = x.send(:read_chunk,data)
    expect(s).to be(:eof)
    expect(ieof).to be_truthy
  end
end

describe ICAPrb::Server::ICAPRequestParser do
  it 'parses an icap request correctly' do
    request = "REQMOD icap://localhost/echo ICAP/1.0\r\n" +
              "Host: localhost\r\n" +
              "User-Agent: ICAP-Client\r\n" +
              "Preview: 512\r\n" +
              "Encapsulated: res-hdr=0\r\n\r\n"
    io = StringIO.new(request)
    io.rewind

    icap_request_parser = ICAPrb::Server::ICAPRequestParser.new(io)
    data = icap_request_parser.parse

    expect(data[:request_line][:icap_method]).to eq(:request_mod)
    expect(data[:request_line][:uri].to_s).to eq('icap://localhost/echo')
    expect(data[:request_line][:version].to_s).to eq('1.0')

    header = data[:header]
    expect(header['Encapsulated']).to eq('res-hdr=0')
    expect(header['Preview']).to eq('512')
    expect(header['User-Agent']).not_to eq('TEST')
  end

  it 'raises an exception if the request line of an ICAP request is incorrect' do
    icap_request_parser = ICAPrb::Server::ICAPRequestParser.new(nil)
    expect {icap_request_parser.parse_icap_request_line("TEST icap://localhost/echo ICAP/1.0\r\n")}.
        to raise_error(ICAPrb::Server::Parser::ICAP_Parse_Error)
    expect {icap_request_parser.parse_icap_request_line("REQMOD icap://localhost:error/echo ICAP/1.0\r\n")}.
        to raise_error(URI::InvalidURIError)
    expect {icap_request_parser.parse_icap_request_line("REQMOD icap://localhost/echo HTTP/1.0\r\n")}.
        to raise_error(ICAPrb::Server::Parser::ICAP_Parse_Error)
  end

end