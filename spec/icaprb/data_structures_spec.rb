require 'spec_helper'

describe ICAPrb::Server do
  it 'does sort the headers correctly' do
    reb = ICAPrb::Server::ResponseBody.new('test')
    rqb = ICAPrb::Server::RequestBody.new('test')
    reh = ICAPrb::Server::ResponseHeader.new('1.1', 200)
    rqh = ICAPrb::Server::RequestHeader.new('GET','/home','1.1')
    nb = ICAPrb::Server::NullBody.new
    arr = reb, reh, nb, rqb, rqh
    arr_sorted = arr.sort
    expect(arr_sorted[0]).to eq rqh
    expect(arr_sorted[1]).to eq reh
    expect(arr_sorted[2]).to be_a_kind_of String
    expect(arr_sorted[3]).to be_a_kind_of String
    expect(arr_sorted[4]).to eq nb
  end

  it 'creates a string from http response headers correctly' do
    rh = ICAPrb::Server::ResponseHeader.new('1.1', 200)
    rh['Server'] = 'ICAP.rb'
    expect(rh.to_s).to eq "HTTP/1.1 200 OK\r\nServer: ICAP.rb\r\n\r\n"
  end

  it 'creates a string from http request headers correctly' do
    rh = ICAPrb::Server::RequestHeader.new('GET','/home','1.1')
    rh['User-Agent'] = 'ICAP.rb'
    expect(rh.to_s).to eq("GET /home HTTP/1.1\r\nUser-Agent: ICAP.rb\r\n\r\n")
  end

  it 'stores the ieof flag' do
    rb1 = ICAPrb::Server::RequestBody.new('test', false)
    rb2 = ICAPrb::Server::RequestBody.new('test',true)

    expect(rb1.ieof).to be_falsey
    expect(rb2.ieof).to be_truthy

    rb1.ieof=true

    expect(rb1.ieof).to be_truthy
  end
end