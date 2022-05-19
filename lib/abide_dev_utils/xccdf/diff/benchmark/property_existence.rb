# frozen_string_literal: true

module AbideDevUtils
  module XCCDF
    module Diff
      # PropertyExistenceChecker provides methods to check existence state of various properties
      class PropertyExistenceChecker
        def initialize(*_args); end

        # Compares two arrays (or other iterables implementing `#to_a`)
        # containing properies and returns an array of the properties
        # that are added by other_props but not in self_props.
        def added(self_props, other_props)
          other_props.to_a - self_props.to_a
        end

        # Compares two arrays (or other iterables implementing `#to_a`)
        # containing properies and returns an array of the properties
        # that are removed by other_props but exist in self_props.
        def removed(this, other)
          this.to_a - other.to_a
        end

        # Returns a hash of existence states and their inverse.
        def self.inverse_existence_state
          {
            removed: :added,
            added: :removed,
            exists: :exists,
          }
        end

        private

        def property_existence(property, self_props, other_props)
          if self_props.include?(property) && !other_props.include?(property)
            :removed
          elsif !self_props.include?(property) && other_props.include?(property)
            :added
          else
            :exists
          end
        end
      end
    end
  end
end
