# frozen_string_literal: true

module ResilientCall
  # Global, thread-safe registry of named Circuit instances.
  module CircuitBreaker
    @registry = {}
    @mutex    = Mutex.new

    # Returns the circuit for `name`, creating it on first access. Created with
    # default thresholds and the globally configured storage; the entry point
    # injects the configured thresholds through Circuit#update_config.
    def self.[](name)
      @mutex.synchronize do
        @registry[name] ||= Circuit.new(name, storage: ResilientCall.configuration.circuit_storage)
      end
    end

    def self.reset_all!
      @mutex.synchronize { @registry.each_value(&:reset!) }
    end
  end
end
