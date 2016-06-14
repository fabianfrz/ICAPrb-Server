#
require "bundler/setup"
require "icaprb/server"
require 'logger'
include ICAPrb::Server

trap('SIGINT') { exit! 0 }
########################################################################
#                  DIFFERENT WAYS TO RUN THE SERVER                    #
########################################################################

# normal socket
#s = ICAPServer.new
# puts 'Server is running on port 1344. Press CTRL+C to exit...'

# squid v4 variant
#options = {secure: true,
#          certificate: '../cert.pem',
#          key: '../key.pem',
#          tls_socket: true}
#s = ICAPServer.new('localhost',11344,options)
# puts 'Server is running on port 11344. Press CTRL+C to exit...'

# rfc 3507 variant
options = {secure: true,
           certificate: '../cert.pem',
           key: '../key.pem',
           tls_socket: false}
s = ICAPServer.new('localhost',1344,options)
puts 'Server is running on port 1344. Press CTRL+C to exit...'

########################################################################
s.logger.level = Logger::INFO
s.services['echo'] = Services::EchoService.new

s.run
