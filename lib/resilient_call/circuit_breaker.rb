# frozen_string_literal: true

module ResilientCall
  # Global, thread-safe registry of named Circuit instances.
  module CircuitBreaker
    @registry = {}
    @mutex    = Mutex.new

    # Returns the circuit for `name`, creating it on first access. Created with
    # the scope-3 defaults (threshold: 5, reset_timeout: 60); scope 4 will inject
    # configured values through the entry point.
    def self.[](name)
      @mutex.synchronize { @registry[name] ||= Circuit.new(name) }
    end

    def self.reset_all!
      @mutex.synchronize { @registry.each_value(&:reset!) }
    end
  end
end
