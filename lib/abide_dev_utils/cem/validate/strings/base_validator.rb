# frozen_string_literal: true

require_relative 'validation_finding'

module AbideDevUtils
  module CEM
    module Validate
      module Strings
        # Base class for validating Puppet Strings objects. This class can be used directly, but it is
        # recommended to use a subclass of this class to provide more specific validation logic. Each
        # subclass should implement a `validate_<type>` method that will be called by the `validate` method
        # of this class. The `validate_<type>` method should contain the validation logic for the
        # corresponding type of Puppet Strings object.
        class BaseValidator
          SAFE_OBJECT_METHODS = %i[
            type
            name
            file
            line
            docstring
            tags
            parameters
            source
          ].freeze
          PDK_SUMMARY_REGEX = %r{^A short summary of the purpose.*}.freeze
          PDK_DESCRIPTION_REGEX = %r{^A description of what this.*}.freeze

          attr_reader :findings

          def initialize(strings_object)
            @object = strings_object
            @findings = []
            # Define instance methods for each of the SAFE_OBJECT_METHODS
            SAFE_OBJECT_METHODS.each do |method|
              define_singleton_method(method) { safe_method_call(@object, method) }
            end
          end

          def errors
            @findings.select { |f| f.type == :error }
          end

          def warnings
            @findings.select { |f| f.type == :warning }
          end

          def errors?
            !errors.empty?
          end

          def warnings?
            !warnings.empty?
          end

          def find_tag_name(tag_name)
            tags&.find { |t| t.tag_name == tag_name }
          end

          def select_tag_name(tag_name)
            return [] if tags.nil?

            tags.select { |t| t.tag_name == tag_name }
          end

          def find_parameter(param_name)
            parameters&.find { |p| p[0] == param_name }
          end

          def validate
            license_tag?
            non_generic_summary?
            non_generic_description?
            send("validate_#{type}".to_sym) if respond_to?("validate_#{type}".to_sym)
          end

          # Checks if the object has a license tag and if it is formatted correctly.
          # Comparison is not case sensitive.
          def license_tag?
            see_tags = select_tag_name('see')
            if see_tags.empty? || see_tags.none? { |t| t.name.casecmp('LICENSE.pdf') && t.text.casecmp('for license') }
              new_finding(
                :error,
                :no_license_tag,
                remediation: 'Add "@see LICENSE.pdf for license" to the class documentation'
              )
              return false
            end
            true
          end

          # Checks if the summary is not the default PDK summary.
          def non_generic_summary?
            summary = find_tag_name('summary')&.text
            return true if summary.nil?

            if summary.match?(PDK_SUMMARY_REGEX)
              new_finding(:warning, :generic_summary, remediation: 'Add a more descriptive summary')
              return false
            end
            true
          end

          # Checks if the description is not the default PDK description.
          def non_generic_description?
            description = docstring
            return true if description.nil?

            if description.match?(PDK_DESCRIPTION_REGEX)
              new_finding(:warning, :generic_description, remediation: 'Add a more descriptive description')
              return false
            end
            true
          end

          private

          def safe_method_call(obj, method, *args)
            obj.send(method, *args)
          rescue NoMethodError
            nil
          end

          def new_finding(type, title, **data)
            @findings << ValidationFinding.new(type, title.to_sym, data)
          end
        end
      end
    end
  end
end
