# frozen_string_literal: true

require_relative 'base_validator'
require_relative '../../../validate'

module AbideDevUtils
  module Sce
    module Validate
      module Strings
        # Validates a Puppet Class from a Puppet Strings hash
        class PuppetClassValidator < BaseValidator
          def validate_puppet_class
            check_text_or_summary
            check_params
          end

          # @return [Hash] Hash of basic class data to be used in findings
          def finding_data(**data)
            data
          end

          private

          # Checks if the class has a description or summary
          def check_text_or_summary
            valid_desc = AbideDevUtils::Validate.populated_string?(docstring)
            valid_summary = AbideDevUtils::Validate.populated_string?(find_tag_name('summary')&.text)
            return if valid_desc || valid_summary

            new_finding(
              :error,
              :no_description_or_summary,
              finding_data(valid_description: valid_desc, valid_summary: valid_summary)
            )
          end

          # Checks if the class has parameters and if they are documented
          def check_params
            return if parameters.nil? || parameters.empty? # No params

            param_tags = select_tag_name('param')
            if param_tags.empty?
              new_finding(:error, :no_parameter_documentation, finding_data(class_parameters: parameters))
              return
            end

            parameters.each do |param|
              param_name, def_val = param
              check_param(param_name, def_val, param_tags)
            end
          end

          # Checks if a parameter is documented properly and if it has a correct default value
          def check_param(param_name, def_val = nil, param_tags = select_tag_name('param'))
            param_tag = param_tags.find { |t| t.name == param_name }
            return unless param_documented?(param_name, param_tag)

            valid_param_description?(param_tag)
            valid_param_types?(param_tag)
            valid_param_default?(param_tag, def_val)
          end

          # Checks if a parameter is documented
          def param_documented?(param_name, param_tag)
            return true if param_tag

            new_finding(:error, :param_not_documented, finding_data(param: param_name))
            false
          end

          # Checks if a parameter has a description
          def valid_param_description?(param)
            return true if AbideDevUtils::Validate.populated_string?(param.text)

            new_finding(:error, :param_missing_description, finding_data(param: param.name))
            false
          end

          # Checks if a parameter is typed
          def valid_param_types?(param)
            unless param.types&.any?
              new_finding(:error, :param_missing_types, finding_data(param: param.name))
              return false
            end
            true
          end

          # Checks if a parameter has a default value and if it is correct for the type
          def valid_param_default?(param, def_val)
            return true if def_val.nil?

            if param.types.first.start_with?('Optional[') && def_val != 'undef'
              new_finding(:error, :param_optional_without_undef_default, param: param.name, default_value: def_val,
                                                                         name: name, file: file)
              return false
            end
            true
          end
        end
      end
    end
  end
end
