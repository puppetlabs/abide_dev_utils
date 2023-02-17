# frozen_string_literal: true

require_relative '../../ppt/strings'
require_relative 'strings/puppet_class_validator'
require_relative 'strings/puppet_defined_type_validator'

module AbideDevUtils
  module CEM
    module Validate
      # Validation objects and methods for Puppet Strings
      module Strings
        # Convenience method to validate Puppet Strings of current module
        def self.validate(**opts)
          output = Validator.new(nil, **opts).validate
          output.transform_values do |results|
            results.select { |r| r[:errors].any? || r[:warnings].any? }
          end
        end

        # Holds various validation methods for a AbideDevUtils::Ppt::Strings object
        class Validator
          def initialize(puppet_strings = nil, **opts)
            unless puppet_strings.nil? || puppet_strings.is_a?(AbideDevUtils::Ppt::Strings)
              raise ArgumentError, 'If puppet_strings is supplied, it must be a AbideDevUtils::Ppt::Strings object'
            end

            puppet_strings = AbideDevUtils::Ppt::Strings.new(**opts) if puppet_strings.nil?
            @puppet_strings = puppet_strings
          end

          # Associate validators with each Puppet Strings object and calls #validate on each
          # @return [Hash] Hash of validation results
          def validate
            AbideDevUtils::Ppt::Strings::REGISTRY_TYPES.each_with_object({}) do |rtype, hsh|
              next unless rtype.to_s.start_with?('puppet_') && @puppet_strings.respond_to?(rtype)

              hsh[rtype] = @puppet_strings.send(rtype).map do |item|
                item.validator = validator_for(item)
                item.validate
                validation_output(item)
              end
            end
          end

          private

          # Returns the appropriate validator for a given Puppet Strings object
          def validator_for(item)
            case item.type
            when :puppet_class
              PuppetClassValidator.new(item)
            when :puppet_defined_type
              PuppetDefinedTypeValidator.new(item)
            else
              BaseValidator.new(item)
            end
          end

          def validation_output(item)
            {
              name: item.name,
              file: item.file,
              line: item.line,
              errors: item.errors,
              warnings: item.warnings,
            }
          end

          # Validate Puppet Class strings hashes.
          # @return [Hash] Hash of class names and errors
          def validate_classes!
            @puppet_strings.puppet_classes.map! do |klass|
              klass.validator = PuppetClassValidator.new(klass)
              klass.validate
              klass
            end
          end
        end
      end
    end
  end
end
