# frozen_string_literal: true

module ResilientCall
  module Storage
    # Contract every storage backend must implement. A storage persists the
    # mutable state of each named circuit as a serializable Hash:
    #
    #   { status:, failure_count:, opened_at:, last_failure_message:, last_failure_class: }
    #
    # Backends decide *where* that state lives (process memory, Redis, ...); the
    # Circuit stays agnostic and only reads/writes through this interface.
    class Base
      def read(circuit_name)
        raise NotImplementedError, "#{self.class}#read"
      end

      def write(circuit_name, state)
        raise NotImplementedError, "#{self.class}#write"
      end

      def reset(circuit_name)
        raise NotImplementedError, "#{self.class}#reset"
      end

      def reset_all
        raise NotImplementedError, "#{self.class}#reset_all"
      end
    end
  end
end
