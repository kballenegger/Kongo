# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'kongo/version'

Gem::Specification.new do |gem|
  gem.name          = 'kongo'
  gem.version       = Kongo::VERSION
  gem.authors       = ['Kenneth Ballenegger']
  gem.email         = ['kenneth@ballenegger.com']
  gem.description   = %q{Kongo is a lightweight and generic library for accessing data from Mongo.}
  gem.homepage      = 'https://github.com/kballenegger/Kongo'

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ['lib']
  
  gem.add_dependency('mongo', '>= 1.7.0')
end
