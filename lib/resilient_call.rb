# frozen_string_literal: true

require_relative "resilient_call/version"
require_relative "resilient_call/errors"
# Additional requires (configuration, retrier, circuit, circuit_breaker, mixin)
# will be added in upcoming scopes.

module ResilientCall
  class << self
    def call(**options, &block)
      raise NotImplementedError, "Coming in a future release"
    end
  end
end
