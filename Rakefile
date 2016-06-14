require "bundler/gem_tasks"
require "rspec/core/rake_task"
require 'rdoc/task'

RSpec::Core::RakeTask.new(:spec)

RDoc::Task.new do |rdoc|
  rdoc.main = 'README.rdoc'
  rdoc.rdoc_files.include('README.rdoc', 'lib/**/*.rb')
end

desc 'search for undocumented things'
task :not_documented do
  sh 'rdoc --dry-run -V 2> /dev/null | grep "(undocumented)" | sed -E "s/^\\s+//g"'
end

task :default => :spec
