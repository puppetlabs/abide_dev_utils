# frozen_string_literal: true

require 'abide_dev_utils/dot_number_comparable'
require 'abide_dev_utils/errors'
require 'abide_dev_utils/cem/hiera_data/mapping_data'
require 'abide_dev_utils/cem/hiera_data/resource_data/parameters'

module AbideDevUtils
  module CEM
    module HieraData
      module ResourceData
        # Represents a singular rule in a benchmark
        class Control
          include AbideDevUtils::DotNumberComparable
          attr_reader :id, :parameters, :resource, :framework

          def initialize(id, params, resource, framework, mapper)
            validate_id_with_framework(id, framework, mapper)
            @id = id
            @parameters = Parameters.new(params)
            @resource = resource
            @framework = framework
            @mapper = mapper
            raise AbideDevUtils::Errors::NoMappingDataForControlError, @id unless @mapper.get(id)
          end

          def alternate_ids(level: nil, profile: nil)
            id_map = @mapper.get(id, level: level, profile: profile)
            if display_title_type.to_s == @mapper.map_type(id)
              id_map
            else
              alt_ids = id_map.each_with_object([]) do |mapval, arr|
                arr << if display_title_type.to_s == @mapper.map_type(mapval)
                         @mapper.get(mapval, level: level, profile: profile)
                       else
                         mapval
                       end
              end
              alt_ids.flatten.uniq
            end
          end

          def id_map_type
            @mapper.map_type(id)
          end

          def display_title
            send(display_title_type) unless display_title_type.nil?
          end

          def levels
            levels_and_profiles[0]
          end

          def profiles
            levels_and_profiles[1]
          end

          def method_missing(meth, *args, &block)
            meth_s = meth.to_s
            if AbideDevUtils::CEM::HieraData::MappingData::ALL_TYPES.include?(meth_s)
              @mapper.get(id).find { |x| @mapper.map_type(x) == meth_s }
            else
              super
            end
          end

          def respond_to_missing?(meth, include_private = false)
            AbideDevUtils::CEM::HieraData::MappingData::ALL_TYPES.include?(meth.to_s) || super
          end

          def to_h
            {
              id: id,
              display_title: display_title,
              alternate_ids: alternate_ids,
              levels: levels,
              profiles: profiles,
              resource: resource,
            }.merge(parameters.to_h)
          end

          private

          def display_title_type
            if (!vulnid.nil? && !vulnid.is_a?(String)) || !title.is_a?(String)
              nil
            elsif framework == 'stig' && vulnid
              :vulnid
            else
              :title
            end
          end

          def validate_id_with_framework(id, framework, mapper)
            mtype = mapper.map_type(id)
            return if AbideDevUtils::CEM::HieraData::MappingData::FRAMEWORK_TYPES[framework].include?(mtype)

            raise AbideDevUtils::Errors::ControlIdFrameworkMismatchError, [id, mtype, framework]
          end

          def map
            @map ||= @mapper.get(id)
          end

          def levels_and_profiles
            @levels_and_profiles ||= find_levels_and_profiles
          end

          def find_levels_and_profiles
            lvls = []
            profs = []
            @mapper.levels.each do |lvl|
              @mapper.profiles.each do |prof|
                unless @mapper.get(id, level: lvl, profile: prof).nil?
                  lvls << lvl
                  profs << prof
                end
              end
            end
            [lvls.flatten.compact.uniq, profs.flatten.compact.uniq]
          end
        end
      end
    end
  end
end
