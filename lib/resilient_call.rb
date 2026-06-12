# frozen_string_literal: true

require_relative "resilient_call/version"
require_relative "resilient_call/errors"
require_relative "resilient_call/configuration"
require_relative "resilient_call/circuit"
require_relative "resilient_call/circuit_breaker"
require_relative "resilient_call/retrier"
# require_relative "resilient_call/mixin" — added in scope 5 once the file exists.

module ResilientCall
  class << self
    # Runs `block` with retry and, when `circuit:` is given, circuit-breaker
    # protection. Option precedence: inline > profile > global config > defaults.
    def call(**options, &block)
      merged = configuration.to_h

      if (profile_name = options.delete(:profile))
        profile = configuration.profiles[profile_name] || {}
        merged  = merged.merge(profile)
      end

      merged = merged.merge(options)

      circuit = nil
      if (circuit_name = merged[:circuit])
        circuit = CircuitBreaker[circuit_name]
        circuit.update_config(
          threshold:     merged[:threshold],
          reset_timeout: merged[:reset_timeout]
        )

        unless circuit.allow_request?
          if (fallback = merged[:fallback])
            return fallback.call
          end

          raise CircuitOpenError.new(
            circuit_name: circuit_name,
            opens_at:     circuit.opened_at,
            retry_after:  (circuit.opened_at + merged[:reset_timeout] - Time.now).to_i,
            last_error:   circuit.last_failure
          )
        end
      end

      Retrier.new(merged).call do
        result = block.call
        circuit&.record_success!
        result
      rescue StandardError => e
        circuit&.record_failure!(e)
        raise
      end
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
  end
end
