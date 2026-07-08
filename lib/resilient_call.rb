# frozen_string_literal: true

require_relative "resilient_call/version"
require_relative "resilient_call/errors"
require_relative "resilient_call/configuration"
require_relative "resilient_call/circuit"
require_relative "resilient_call/circuit_breaker"
require_relative "resilient_call/retrier"
require_relative "resilient_call/mixin"

module ResilientCall
  class << self
    # Runs `block` with retry and, when `circuit:` is given, circuit-breaker
    # protection. Option precedence: inline > profile > global config > defaults.
    def call(**options, &block)
      options = resolve_options(options)
      circuit = circuit_for(options)

      return reject_open_circuit(circuit, options) if circuit_blocking?(circuit)

      run_with_retry(options, circuit, &block)
    end

    def configure
      yield configuration
    end

    def configuration
      @configuration ||= Configuration.new
    end

    def define_profile(name, **options)
      configuration.profiles[name] = options
    end

    # Restores global defaults — useful for isolating tests.
    def reset_configuration!
      @configuration = Configuration.new
    end

    private

    # Merges defaults < profile < inline options into a single options hash.
    def resolve_options(options)
      merged = configuration.to_h

      if (profile_name = options.delete(:profile))
        merged = merged.merge(configuration.profiles[profile_name] || {})
      end

      merged.merge(options)
    end

    # Resolves the named circuit (if any) and applies the configured thresholds.
    def circuit_for(options)
      return unless (name = options[:circuit])

      CircuitBreaker[name].tap do |circuit|
        circuit.update_config(
          threshold:     options[:threshold],
          reset_timeout: options[:reset_timeout]
        )
      end
    end

    # True when a circuit exists and is currently rejecting requests.
    def circuit_blocking?(circuit)
      circuit && !circuit.allow_request?
    end

    # Handles a request blocked by an open circuit: runs the fallback if one
    # was given, otherwise raises CircuitOpenError.
    def reject_open_circuit(circuit, options)
      return options[:fallback].call if options[:fallback]

      raise circuit_open_error(circuit, options)
    end

    def circuit_open_error(circuit, options)
      CircuitOpenError.new(
        circuit_name: options[:circuit],
        opens_at:     circuit.opened_at,
        retry_after:  (circuit.opened_at + options[:reset_timeout] - Time.now).to_i,
        last_error:   circuit.last_failure
      )
    end

    # Runs the block through the Retrier, feeding circuit outcomes as it goes.
    def run_with_retry(options, circuit, &block)
      Retrier.new(options).call do
        result = block.call
        circuit&.record_success!
        result
      rescue StandardError => e
        circuit&.record_failure!(e)
        raise
      end
    end
  end
end
