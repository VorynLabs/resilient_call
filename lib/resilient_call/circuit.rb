# frozen_string_literal: true

require_relative "storage/memory"

module ResilientCall
  # Holds the state of a single named circuit and manages its transitions.
  # The mutable state lives in the injected `storage` (memory by default, Redis
  # for multi-process setups); this class owns only the transition rules.
  #
  # Thread-safe within a process: every read-modify-write runs under an internal
  # Mutex, so concurrent calls on the same instance stay consistent. Across
  # processes, consistency is bounded by the storage backend (see Storage::Redis).
  #
  #   closed --(threshold failures)--> open --(reset_timeout elapsed)--> half_open
  #     ^                                                                     |
  #     +------------------------- record_success! -------------------------+
  #   half_open --(record_failure!)--> open  (restarts the timer)
  class Circuit
    attr_reader :name, :threshold, :reset_timeout

    def initialize(name, threshold: 5, reset_timeout: 60, storage: nil)
      @name          = name
      @threshold     = threshold
      @reset_timeout = reset_timeout
      @storage       = storage || Storage::Memory.new
      @last_failure  = nil
      @mutex         = Mutex.new
    end

    def state
      @mutex.synchronize { read_state[:status] }
    end

    def failure_count
      @mutex.synchronize { read_state[:failure_count] }
    end

    # The full Exception object captured most recently *in this process*. State
    # shared through Redis only carries its message/class, so a fresh process
    # reading an open circuit sees nil here — use CircuitOpenError for details.
    def last_failure
      @mutex.synchronize { @last_failure }
    end

    def opened_at
      @mutex.synchronize { read_state[:opened_at] }
    end

    # Whether a request may pass right now. An :open circuit whose reset_timeout
    # has elapsed transitions to :half_open and lets a single probe through.
    def allow_request?
      @mutex.synchronize do
        state = read_state

        case state[:status]
        when :closed, :half_open
          true
        when :open
          if Time.now - state[:opened_at] >= @reset_timeout
            state[:status] = :half_open
            write_state(state)
            true
          else
            false
          end
        end
      end
    end

    def record_success!
      @mutex.synchronize do
        state = read_state

        case state[:status]
        when :half_open
          state[:status]        = :closed
          state[:failure_count] = 0
        when :closed
          state[:failure_count] = 0
        end

        write_state(state)
      end
    end

    def record_failure!(error)
      @mutex.synchronize do
        @last_failure = error

        state = read_state
        state[:failure_count]       += 1
        state[:last_failure_message] = error.message
        state[:last_failure_class]   = error.class.name

        if state[:status] == :half_open
          state[:status]    = :open
          state[:opened_at] = Time.now
        elsif state[:status] == :closed && state[:failure_count] >= @threshold
          state[:status]    = :open
          state[:opened_at] = Time.now
        end

        write_state(state)
      end
    end

    def reset!
      @mutex.synchronize do
        @last_failure = nil
        @storage.reset(@name)
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

    # Current persisted state, or a fresh :closed state when the circuit has no
    # record yet. Callers mutate the returned Hash and persist via write_state.
    def read_state
      @storage.read(@name) || default_state
    end

    def write_state(state)
      @storage.write(@name, state)
    end

    def default_state
      {
        status:               :closed,
        failure_count:        0,
        opened_at:            nil,
        last_failure_message: nil,
        last_failure_class:   nil
      }
    end
  end
end
