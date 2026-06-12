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
    attr_reader :name, :threshold, :reset_timeout

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

    def state
      @mutex.synchronize { @state }
    end

    def failure_count
      @mutex.synchronize { @failure_count }
    end

    def last_failure
      @mutex.synchronize { @last_failure }
    end

    def opened_at
      @mutex.synchronize { @opened_at }
    end

    # Whether a request may pass right now. An :open circuit whose reset_timeout
    # has elapsed transitions to :half_open and lets a single probe through.
    def allow_request?
      @mutex.synchronize do
        case @state
        when :closed
          true
        when :half_open
          true
        when :open
          if Time.now - @opened_at >= @reset_timeout
            @state = :half_open
            true
          else
            false
          end
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

        if @state == :half_open
          @state     = :open
          @opened_at = Time.now
        elsif @state == :closed && @failure_count >= @threshold
          @state     = :open
          @opened_at = Time.now
        end
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
  end
end
