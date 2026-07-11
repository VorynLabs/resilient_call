# frozen_string_literal: true

module ResilientCall
  # Executes a block with retry, computing the wait between attempts and firing
  # the configured callbacks. Has no knowledge of circuit breakers.
  class Retrier
    DEFAULTS = {
      retries:    3,
      wait:       :exponential,
      base_wait:  0.5,
      max_wait:   30.0,
      jitter:     true,
      on:         [StandardError],
      on_retry:   nil,
      on_failure: nil,
      on_success: nil
    }.freeze

    def initialize(options = {})
      opts = DEFAULTS.merge(options)

      @retries    = opts[:retries]
      @wait       = opts[:wait]
      @base_wait  = opts[:base_wait]
      @max_wait   = opts[:max_wait]
      @jitter     = opts[:jitter]
      @on         = Array(opts[:on])
      @on_retry   = opts[:on_retry]
      @on_failure = opts[:on_failure]
      @on_success = opts[:on_success]
    end

    def call
      attempt = 0

      begin
        attempt += 1
        result = yield
        on_success&.call(result, attempt)
        result
      rescue *on => err
        raise_exhausted(err, attempt) unless retryable?(attempt)

        on_retry&.call(attempt, err)
        sleep(wait_time(attempt))
        retry
      end
    end

    private

    attr_reader :retries, :wait, :base_wait, :max_wait, :jitter,
                :on, :on_retry, :on_failure, :on_success

    # True while retries remain. `attempt` is the 1-based number that just ran.
    def retryable?(attempt)
      attempt <= retries
    end

    def raise_exhausted(err, attempt)
      on_failure&.call(err)
      # Raised inside the rescue so Ruby populates #cause with `err`.
      raise RetriesExhaustedError.new(attempts: attempt)
    end

    def wait_time(attempt)
      [with_jitter(base_delay(attempt)), max_wait].min
    end

    def base_delay(attempt)
      case wait
      when :exponential
        base_wait * (2**attempt)
      when :linear
        base_wait * attempt
      when :fixed
        base_wait
      when Proc
        wait.call(attempt)
      else
        raise ArgumentError, "unknown wait strategy: #{wait.inspect}"
      end
    end

    def with_jitter(delay)
      return delay unless jitter

      delay + rand(0..base_wait * 0.3)
    end
  end
end
