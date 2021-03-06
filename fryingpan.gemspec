# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'fryingpan/version'

Gem::Specification.new do |spec|
  spec.name          = "fryingpan"
  spec.version       = Fryingpan::VERSION
  spec.authors       = ["nkaneko"]
  spec.email         = ["nkaneko@iij.ad.jp"]
  spec.summary       = %q{HoneyPot AP on Raspberry Pi}
  spec.description   = %q{Wi-Fi HoneyPot Builder}
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.7"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec"

  spec.add_dependency "sinatra", "~> 1.4.4"
end
