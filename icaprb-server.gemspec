# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'icaprb/server/version'

Gem::Specification.new do |spec|
  spec.name          = 'icaprb-server'
  spec.version       = ICAPrb::Server::VERSION
  spec.authors       = ['Fabian Franz']
  spec.email         = ['fabian.franz@students.fh-hagenberg.at']
  spec.license       = 'BSD-2-Clause'
  spec.required_ruby_version = '>= 2.0.0'

  spec.summary       = %q{This project includes an ICAP server fully implemented in Ruby but it does not include services.}
  spec.homepage      = 'https://github.com/fabianfrz/ICAPrb-Server'

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_development_dependency 'bundler', '~> 1.11'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
end
