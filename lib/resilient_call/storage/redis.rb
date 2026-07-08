# frozen_string_literal: true

require "json"
require_relative "base"

module ResilientCall
  module Storage
    # Shares circuit state across processes through Redis. The Redis client is
    # injected, so this class has no hard dependency on the `redis` gem itself —
    # any object answering to get/set/del/keys works (including fakes in tests).
    #
    # Concurrency note: read + write are separate round-trips, so two processes
    # can race on the failure counter. The worst case is an occasional missed
    # increment, never state corruption. Atomic Lua updates are a v0.3 concern.
    class Redis < Base
      KEY_PREFIX = "resilient_call:circuit:"

      def initialize(redis_client)
        @redis = redis_client
      end

      def read(circuit_name)
        raw = @redis.get(key_for(circuit_name))
        raw ? deserialize(raw) : nil
      end

      def write(circuit_name, state)
        @redis.set(key_for(circuit_name), serialize(state))
      end

      def reset(circuit_name)
        @redis.del(key_for(circuit_name))
      end

      def reset_all
        keys = @redis.keys("#{KEY_PREFIX}*")
        @redis.del(*keys) unless keys.empty?
      end

      private

      def key_for(circuit_name)
        "#{KEY_PREFIX}#{circuit_name}"
      end

      def serialize(state)
        JSON.generate(state.merge(opened_at: state[:opened_at]&.to_i))
      end

      def deserialize(raw)
        parsed = JSON.parse(raw, symbolize_names: true)
        parsed[:status]    = parsed[:status].to_sym if parsed[:status]
        parsed[:opened_at] = Time.at(parsed[:opened_at]) if parsed[:opened_at]
        parsed
      end
    end
  end
end
