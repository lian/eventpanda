# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib/', __FILE__)
$:.unshift lib unless $:.include?(lib)
 
require 'eventpanda/version'
 
Gem::Specification.new do |s|
  s.name        = "eventpanda"
  s.version     = EventPanda::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Julian Langschaedel"]
  s.email       = ["meta.rb@gmail.com"]
  s.homepage    = "http://github.com/lian/eventpanda"
  s.summary     = "ffi bindings for libevent with eventmachine api"
  #s.description = 
 
  s.required_rubygems_version = ">= 1.3.7"
  #s.rubyforge_project         = "eventpanda"
 
  s.add_development_dependency "bacon"

  s.add_dependency "ffi"
 
  s.files        = Dir.glob("{bin,lib}/**/*") + %w(COPYING README.md)
  #s.executables  = ['eventpanda']
  s.require_path = 'lib'
end
