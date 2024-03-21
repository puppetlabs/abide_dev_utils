# frozen_string_literal: true

require 'set'
require 'abide_dev_utils/errors'
require 'abide_dev_utils/sce/hiera_data/resource_data/control'
require 'abide_dev_utils/sce/hiera_data/resource_data/parameters'

module AbideDevUtils
  module Sce
    module HieraData
      module ResourceData
        # Represents a resource data resource statement
        class Resource
          attr_reader :title, :type

          def initialize(title, data, framework, mapper)
            @title = title
            @data = data
            @type = data['type']
            @framework = framework
            @mapper = mapper
          end

          def controls
            @controls ||= load_controls
          end

          def sce_options
            @sce_options ||= Parameters.new(data['sce_options'])
          end

          def sce_protected
            @sce_protected ||= Parameters.new(data['sce_protected'])
          end

          def to_stubbed_h
            {
              title: title,
              type: type,
              sce_options: sce_options.to_h,
              sce_protected: sce_protected.to_h,
              reference: to_reference
            }
          end

          def to_reference
            "#{type.split('::').map(&:capitalize).join('::')}['#{title}']"
          end

          def to_puppet_code
            parray = controls.map { |x| x.parameters.to_puppet_code if x.parameters.exist? }.flatten.compact.uniq
            return "#{type} { '#{title}': }" if parray.empty? || parray.all?(&:empty?) || parray.all?("\n")

            # if title == 'sce_linux::utils::packages::linux::auditd::time_change'
            #   require 'pry'
            #   binding.pry
            # end
            <<~EOPC
              #{type} { '#{title}':
              #{parray.join("\n")}
              }
            EOPC
          end

          private

          attr_reader :data, :framework, :mapper

          def load_controls
            if data['controls'].respond_to?(:keys)
              load_hash_controls(data['controls'], framework, mapper)
            elsif data['controls'].respond_to?(:each_with_index)
              load_array_controls(data['controls'], framework, mapper)
            else
              raise "Control type is invalid. Type: #{data['controls'].class}"
            end
          end

          def load_hash_controls(ctrls, framework, mapper)
            ctrls.each_with_object([]) do |(name, data), arr|
              ctrl = Control.new(name, data, to_stubbed_h, framework, mapper)
              arr << ctrl
            rescue AbideDevUtils::Errors::ControlIdFrameworkMismatchError,
                   AbideDevUtils::Errors::NoMappingDataForControlError
              next
            end
          end

          def load_array_controls(ctrls, framework, mapper)
            ctrls.each_with_object([]) do |c, arr|
              ctrl = Control.new(c, 'no_params', to_stubbed_h, framework, mapper)
              arr << ctrl
            rescue AbideDevUtils::Errors::ControlIdFrameworkMismatchError,
                   AbideDevUtils::Errors::NoMappingDataForControlError
              next
            end
          end
        end
      end
    end
  end
end
