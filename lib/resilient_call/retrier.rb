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

    # Runs the block. Returns its result, or raises RetriesExhaustedError once
    # every attempt has been consumed.
    def call
      attempt = 0

      begin
        attempt += 1
        result = yield
        @on_success&.call(result, attempt)
        result
      rescue *@on => err
        if attempt <= @retries
          @on_retry&.call(attempt, err)
          sleep(wait_time(attempt))
          retry
        end

        @on_failure&.call(err)
        # Raised inside the rescue so Ruby populates #cause with `err`.
        raise RetriesExhaustedError.new(attempts: attempt)
      end
    end

    private

    # 1-based attempt number. Applies jitter before capping at max_wait.
    def wait_time(attempt)
      raw = case @wait
            when :exponential then @base_wait * (2**attempt)
            when :linear      then @base_wait * attempt
            when :fixed       then @base_wait
            when Proc         then @wait.call(attempt)
            else
              raise ArgumentError, "unknown wait strategy: #{@wait.inspect}"
            end

      raw += rand(0..@base_wait * 0.3) if @jitter
      [raw, @max_wait].min
    end
  end
end
