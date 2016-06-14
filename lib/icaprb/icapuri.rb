# = icaprb/server/icapuri.rb
# Author:: Fabian Franz
#
# See URI for general documentation
#

require 'uri/generic'

module URI #:nodoc:

  # Class to represent ICAP URIs
  class ICAP < Generic
    # The ICAP default port is 1344
    DEFAULT_PORT = 1344
  end
  # Class to represent ICAP URIs
  class ICAPS < Generic
    # The ICAP default port is 11344
    DEFAULT_PORT = 11344
  end

  @@schemes['ICAP'] = ICAP
  @@schemes['ICAPS'] = ICAPS
end
