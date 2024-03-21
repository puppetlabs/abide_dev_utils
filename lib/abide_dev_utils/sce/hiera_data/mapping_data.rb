# frozen_string_literal: true

require 'abide_dev_utils/sce/hiera_data/mapping_data/map_data'
require 'abide_dev_utils/sce/hiera_data/mapping_data/mixins'

module AbideDevUtils
  module Sce
    module HieraData
      module MappingData
        ALL_TYPES = %w[hiera_title_num number hiera_title vulnid title].freeze
        FRAMEWORK_TYPES = {
          'cis' => %w[hiera_title_num number hiera_title title],
          'stig' => %w[hiera_title_num number hiera_title vulnid title]
        }.freeze
        CIS_TYPES = %w[hiera_title_num number hiera_title title].freeze
        STIG_TYPES = %w[hiera_title_num number hiera_title vulnid title].freeze

        # Handles interacting with mapping data
        class Mapper
          attr_reader :module_name, :framework, :map_data

          def initialize(module_name, framework, map_data)
            @module_name = module_name
            @framework = framework
            load_framework(@framework)
            @map_data = map_data.map { |_, v| MapData.new(v) }
            @cache = {}
            @rule_cache = {}
          end

          def title
            @title ||= benchmark_data['title']
          end

          def version
            @version ||= benchmark_data['version']
          end

          def levels
            @levels ||= default_map_data.levels
          end

          def profiles
            @profiles ||= default_map_data.profiles
          end

          def each_like(identifier)
            identified_map_data(identifier)&.each { |key, val| yield key, val }
          end

          def each_with_array_like(identifier)
            identified_map_data(identifier)&.each_with_object([]) { |(key, val), ary| yield [key, val], ary }
          end

          def get(control_id, level: nil, profile: nil)
            identified_map_data(control_id)&.get(control_id, level: level, profile: profile)
          end

          def map_type(control_id)
            return control_id if ALL_TYPES.include?(control_id)

            case control_id
            when %r{^c[0-9_]+$}
              'hiera_title_num'
            when %r{^[0-9][0-9.]*$}
              'number'
            when %r{^[a-z][a-z0-9_]+$}
              'hiera_title'
            when %r{^V-[0-9]{6}$}
              'vulnid'
            else
              'title'
            end
          end

          private

          def load_framework(framework)
            case framework.downcase
            when 'cis'
              self.class.include AbideDevUtils::Sce::HieraData::MappingData::MixinCIS
              extend AbideDevUtils::Sce::HieraData::MappingData::MixinCIS
            when 'stig'
              self.class.include AbideDevUtils::Sce::HieraData::MappingData::MixinSTIG
              extend AbideDevUtils::Sce::HieraData::MappingData::MixinSTIG
            else
              raise "Invalid framework: #{framework}"
            end
          end

          def map_data_by_type(map_type)
            found_map_data = map_data.find { |x| x.type == map_type }
            unless found_map_data
              raise "Failed to find map data with type #{map_type}; Meta: #{{ framework: framework,
                                                                              module_name: module_name }}"
            end

            found_map_data
          end

          def identified_map_data(identifier, valid_types: ALL_TYPES)
            mtype = map_type(identifier)
            return unless FRAMEWORK_TYPES[framework].include?(mtype)

            map_data_by_type(mtype)
          end

          def map_type_and_top_key(identifier)
            mtype = ALL_TYPES.include?(identifier) ? identifier : map_type(identifier)
            [mtype, map_top_key(mtype)]
          end

          def cached?(control_id, *args)
            @cache.key?(cache_key(control_id, *args))
          end

          def cache_get(control_id, *args)
            ckey = cache_key(control_id, *args)
            @cache[ckey] if cached?(control_id, *args)
          end

          def cache_set(value, control_id, *args)
            @cache[cache_key(control_id, *args)] = value unless value.nil?
          end

          def default_map_type
            @default_map_type ||= (framework == 'stig' ? 'vulnid' : map_data.first.type)
          end

          def default_map_data
            @default_map_data ||= map_data.first
          end

          def benchmark_data
            @benchmark_data ||= default_map_data.benchmark
          end

          def cache_key(control_id, *args)
            args.unshift(control_id).compact.join('-')
          end

          def map_top_key(mtype)
            [module_name, 'mappings', framework, mtype].join('::')
          end
        end
      end
    end
  end
end
