# frozen_string_literal: true

module AbideDevUtils
  module Mixins
    # mixin methods for the Hash data type
    module Hash
      def deep_copy
        Marshal.load(Marshal.dump(self))
      end

      def diff(other)
        dup.delete_if { |k, v| other[k] == v }.merge!(other.dup.delete_if { |k, _| key?(k) })
      end
    end
  end
end
