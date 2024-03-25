# frozen_string_literal: true

require_relative 'puppet_class_validator'

module AbideDevUtils
  module Sce
    module Validate
      module Strings
        # Validates Puppet Defined Type strings objects
        class PuppetDefinedTypeValidator < PuppetClassValidator
          def validate_puppet_defined_type
            validate_puppet_class
          end
        end
      end
    end
  end
end
