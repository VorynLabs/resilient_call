# frozen_string_literal: true

module ResilientCall
  # Adds the `resilient_method` class macro to any class that includes it,
  # wrapping the named instance method in a transparent ResilientCall.call.
  module Mixin
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      # Wraps an already-defined instance method so every invocation runs
      # through ResilientCall.call with the given options (retry, circuit, etc).
      def resilient_method(method_name, **options)
        original = instance_method(method_name)

        define_method(method_name) do |*args, **kwargs, &block|
          ResilientCall.call(**options) do
            original.bind_call(self, *args, **kwargs, &block)
          end
        end
      end
    end
  end
end
