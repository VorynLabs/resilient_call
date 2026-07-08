# frozen_string_literal: true

module ResilientCall
  # Holds the state of a single named circuit and manages its transitions.
  # Thread-safe: every public method runs under an internal Mutex.
  #
  #   closed --(threshold failures)--> open --(reset_timeout elapsed)--> half_open
  #     ^                                                                     |
  #     +------------------------- record_success! -------------------------+
  #   half_open --(record_failure!)--> open  (restarts the timer)
  class Circuit
    attr_reader :name, :threshold, :reset_timeout, :state, :failure_count, :last_failure, :opened_at

    def initialize(name, threshold: 5, reset_timeout: 60)
      @name          = name
      @threshold     = threshold
      @reset_timeout = reset_timeout
      @state         = :closed
      @failure_count = 0
      @opened_at     = nil
      @last_failure  = nil
      @mutex         = Mutex.new
    end

    # Whether a request may pass right now. An :open circuit whose reset_timeout
    # has elapsed transitions to :half_open and lets a single probe through.
    def allow_request?
      @mutex.synchronize do
        case @state
        when :closed then true
        when :half_open then true
        when :open then allow_after_open?
        end
      end
    end

    def record_success!
      @mutex.synchronize do
        case @state
        when :half_open
          @state         = :closed
          @failure_count = 0
        when :closed
          @failure_count = 0
        end
      end
    end

    def record_failure!(error)
      @mutex.synchronize do
        @failure_count += 1
        @last_failure   = error

        open_circuit! if should_open?
      end
    end

    def reset!
      @mutex.synchronize do
        @state         = :closed
        @failure_count = 0
        @opened_at     = nil
        @last_failure  = nil
      end
    end

    # Lets the entry point inject configured thresholds onto a circuit that was
    # created lazily by the registry with default values.
    def update_config(threshold: nil, reset_timeout: nil)
      @mutex.synchronize do
        @threshold     = threshold     unless threshold.nil?
        @reset_timeout = reset_timeout unless reset_timeout.nil?
      end
    end

    private

    def should_open?
      @state == :half_open || (@state == :closed && @failure_count >= @threshold)
    end

    def open_circuit!
      @state     = :open
      @opened_at = Time.now
    end

    def allow_after_open?
      return false unless Time.now - @opened_at >= reset_timeout

      @state = :half_open
      true
    end
  end
end
