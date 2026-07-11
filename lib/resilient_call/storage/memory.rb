# frozen_string_literal: true

require_relative "base"

module ResilientCall
  module Storage
    # Default storage: keeps circuit state in a Hash in the current process.
    # Thread-safe on its own operations via an internal Mutex. State is not
    # shared across processes — use Storage::Redis for multi-worker setups.
    class Memory < Base
      def initialize
        @data  = {}
        @mutex = Mutex.new
      end

      def read(circuit_name)
        @mutex.synchronize { @data[circuit_name] }
      end

      def write(circuit_name, state)
        @mutex.synchronize { @data[circuit_name] = state }
      end

      def reset(circuit_name)
        @mutex.synchronize { @data.delete(circuit_name) }
      end

      def reset_all
        @mutex.synchronize { @data.clear }
      end
    end
  end
end
