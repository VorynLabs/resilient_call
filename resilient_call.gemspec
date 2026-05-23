# frozen_string_literal: true

require_relative "lib/resilient_call/version"

Gem::Specification.new do |spec|
  spec.name          = "resilient_call"
  spec.version       = ResilientCall::VERSION
  spec.authors       = ["Wesley Sena"]
  spec.email         = ["vorynworks@gmail.com"]

  spec.summary       = "Retry with exponential backoff and circuit breaker for Ruby"
  spec.description   = "Wrapper for any Ruby block with configurable retries, jitter, named circuit breaker, declarative fallback, and service class mixin support."
  spec.homepage      = "https://github.com/VorynLabs/resilient_call"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"]      = spec.homepage
  spec.metadata["source_code_uri"]   = "https://github.com/VorynLabs/resilient_call"
  spec.metadata["changelog_uri"]     = "https://github.com/VorynLabs/resilient_call/blob/main/CHANGELOG.md"

  spec.files         = Dir["lib/**/*", "README.md", "LICENSE.txt", "CHANGELOG.md"]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "rake",  "~> 13.0"
end
