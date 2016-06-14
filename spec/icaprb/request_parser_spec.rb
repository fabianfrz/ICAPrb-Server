require 'spec_helper'
require 'stringio'

describe ICAPrb::Server::ICAPRequestParser do
  it 'should parse the request line correctly' do
    o = ::ICAPrb::Server::ICAPRequestParser.new(nil)
    data = o.parse_icap_request_line 'REQMOD icap://localhost/server ICAP/1.0'
    expect(data[:icap_method]).to be :request_mod
    expect(data[:uri]).to eq URI('icap://localhost/server')
    expect(data[:version]).to eq '1.0'
  end

  it 'should throw an exception if the request line is not correct' do
    o = ::ICAPrb::Server::ICAPRequestParser.new(nil)
    expect{o.parse_icap_request_line 'ASDF icap://localhost/server ICAP/1.0'}.
        to raise_error(ICAPrb::Server::Parser::ICAP_Parse_Error)
    expect{o.parse_icap_request_line 'REQMOD icap://:abc:abc:abc/server ICAP/1.0'}.
        to raise_error(URI::InvalidURIError)
  end
end