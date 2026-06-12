# frozen_string_literal: true

module ResilientCall
  # Holds the global defaults and the registry of named profiles.
  class Configuration
    # retry
    attr_accessor :retries, :wait, :base_wait, :max_wait, :jitter, :on
    # circuit breaker
    attr_accessor :threshold, :reset_timeout
    # callbacks
    attr_accessor :on_retry, :on_failure, :on_success
    # named profiles registry
    attr_accessor :profiles

    def initialize
      @retries       = 3
      @wait          = :exponential
      @base_wait     = 0.5
      @max_wait      = 30.0
      @jitter        = true
      @on            = [StandardError]

      @threshold     = 5
      @reset_timeout = 60

      @on_retry      = nil
      @on_failure    = nil
      @on_success    = nil

      @profiles      = {}
    end

    # Every default except the profiles registry, ready to be merged in `.call`.
    def to_h
      {
        retries:       @retries,
        wait:          @wait,
        base_wait:     @base_wait,
        max_wait:      @max_wait,
        jitter:        @jitter,
        on:            @on,
        threshold:     @threshold,
        reset_timeout: @reset_timeout,
        on_retry:      @on_retry,
        on_failure:    @on_failure,
        on_success:    @on_success
      }
    end
  end
end
