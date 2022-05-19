# frozen_string_literal: true

module AbideDevUtils
  module XCCDF
    module Diff
      # Holds the result of a diff on a per-item basis.
      class DiffChangeResult
        attr_reader :type, :old_value, :new_value

        def initialize(type, old_value, new_value)
          @type = type
          @old_value = old_value
          @new_value = new_value
        end

        def to_h
          { type: type, old_value: old_value, new_value: new_value }
        end

        def to_a
          [type, old_value, new_value]
        end

        def to_s
          "#{type}: #{old_value} -> #{new_value}"
        end
      end
    end
  end
end
