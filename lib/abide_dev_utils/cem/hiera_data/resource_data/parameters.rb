# frozen_string_literal: true

require 'set'

module AbideDevUtils
  module CEM
    module HieraData
      module ResourceData
        class Parameters
          def initialize(*param_collections)
            @param_collections = param_collections
          end

          def exist?
            !@param_collections.nil? && !@param_collections.empty?
          end

          def to_h
            @to_h ||= { parameters: @param_collections.map { |x| collection_to_h(x) unless x.nil? || x.empty? } }
          end

          def to_puppet_code
            parray = to_h[:parameters].each_with_object([]) do |x, arr|
              x.each do |_, val|
                arr << param_to_code(**val[:display_value]) if val.respond_to?(:key)
              end
            end
            parray.reject { |x| x.nil? || x.empty? }.compact.join("\n")
          end

          def to_display_fmt
            to_h[:parameters].values.map { |x| x[:display_value] }
          end

          private

          def collection_to_h(collection)
            return no_params_display if collection == 'no_params'

            collection.each_with_object({}) do |(param, param_val), hsh|
              hsh[param] = {
                raw_value: param_val,
                display_value: param_display(param, param_val),
              }
            end
          end

          def param_display(param, param_val)
            {
              name: param,
              type: ruby_class_to_puppet_type(param_val.class.to_s),
              default: param_val,
            }
          end

          def no_params_display
            { name: 'No parameters', type: nil, default: nil }
          end

          def param_to_code(name: nil, type: nil, default: nil)
            return if name.nil?
            return "  #{name}," if default.nil?
            return "  #{name} => #{default}," if %w[Boolean Integer Float].include?(type)
            return "  #{name} => '#{default}'," if type == 'String'

            "  #{name} => undef,"
          end

          def ruby_class_to_puppet_type(class_name)
            pup_type = class_name.split('::').last.capitalize
            case pup_type
            when %r{(Trueclass|Falseclass)}
              'Boolean'
            when %r{(String|Pathname)}
              'String'
            when %r{(Integer|Fixnum)}
              'Integer'
            when %r{(Float|Double)}
              'Float'
            when %r{Nilclass}
              'Optional'
            else
              pup_type
            end
          end
        end
      end
    end
  end
end
