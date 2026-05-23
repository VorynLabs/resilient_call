# frozen_string_literal: true

module ResilientCall
  # Raised when a request is rejected because its named circuit is open.
  class CircuitOpenError < StandardError
    attr_reader :circuit_name, :opens_at, :retry_after, :last_error

    def initialize(circuit_name:, opens_at:, retry_after:, last_error:, message: nil)
      @circuit_name = circuit_name
      @opens_at     = opens_at
      @retry_after  = retry_after
      @last_error   = last_error
      super(message || "circuit #{circuit_name.inspect} is open")
    end
  end

  # Raised when all configured retries have been exhausted without success.
  # The original exception is available through Ruby's native `#cause` chain
  # when this error is raised from inside a rescue block.
  class RetriesExhaustedError < StandardError
    attr_reader :attempts

    def initialize(attempts:, message: nil)
      @attempts = attempts
      super(message || "exhausted after #{attempts} attempt(s)")
    end
  end
end
