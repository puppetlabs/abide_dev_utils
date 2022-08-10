# frozen_string_literal: true

require 'abide_dev_utils/cem/hiera_data/mapping_data/map_data'
require 'abide_dev_utils/cem/hiera_data/mapping_data/mixins'

module AbideDevUtils
  module CEM
    module Mapping
      ALL_TYPES = %w[hiera_title_num number hiera_title vulnid title].freeze
      FRAMEWORK_TYPES = {
        'cis' => %w[hiera_title_num number hiera_title title],
        'stig' => %w[hiera_title_num number hiera_title vulnid title],
      }.freeze
      CIS_TYPES = %w[hiera_title_num number hiera_title title].freeze
      STIG_TYPES = %w[hiera_title_num number hiera_title vulnid title].freeze

      # Represents a single map data file
      class MapData
        def initialize(data)
          @raw_data = data
        end

        def method_missing(meth, *args, &block)
          if data.respond_to?(meth)
            data.send(meth, *args, &block)
          else
            super
          end
        end

        def respond_to_missing?(meth, include_private = false)
          data.respond_to?(meth) || super
        end

        def find(identifier, level: nil, profile: nil)
          levels.each do |lvl|
            next unless level.nil? || lvl != level

            data[lvl].each do |prof, prof_data|
              if prof_data.respond_to?(:keys)
                next unless profile.nil? || prof != profile

                return prof_data[identifier] if prof_data.key?(identifier)
              elsif prof == identifier
                return prof_data
              end
            end
          end
        end

        def get(identifier, level: nil, profile: nil)
          raise "Invalid level: #{level}" unless profile.nil? || levels.include?(level)
          raise "Invalid profile: #{profile}" unless profile.nil? || profiles.include?(profile)
          return find(identifier, level: level, profile: profile) if level.nil? || profile.nil?

          begin
            data.dig(level, profile, identifier)
          rescue TypeError
            data.dig(level, identifier)
          end
        end

        def module_name
          top_key_parts[0]
        end

        def framework
          top_key_parts[2]
        end

        def type
          top_key_parts[3]
        end

        def benchmark
          @raw_data[top_key]['benchmark']
        end

        def levels_and_profiles
          @levels_and_profiles ||= find_levels_and_profiles
        end

        def levels
          levels_and_profiles[0]
        end

        def profiles
          levels_and_profiles[1]
        end

        def top_key
          @top_key ||= @raw_data.keys.first
        end

        private

        def top_key_parts
          @top_key_parts ||= top_key.split('::')
        end

        def data
          @data ||= @raw_data[top_key].reject { |k, _| k == 'benchmark' }
        end

        def find_levels_and_profiles
          lvls = []
          profs = []
          data.each do |lvl, prof_hash|
            lvls << lvl
            prof_hash.each do |prof, prof_data|
              profs << prof if prof_data.respond_to?(:keys)
            end
          end
          [lvls.flatten.compact.uniq, profs.flatten.compact.uniq]
        end
      end

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
            self.class.include AbideDevUtils::CEM::Mapping::MixinCIS
            extend AbideDevUtils::CEM::Mapping::MixinCIS
          when 'stig'
            self.class.include AbideDevUtils::CEM::Mapping::MixinSTIG
            extend AbideDevUtils::CEM::Mapping::MixinSTIG
          else
            raise "Invalid framework: #{framework}"
          end
        end

        def map_data_by_type(map_type)
          found_map_data = map_data.find { |x| x.type == map_type }
          raise "Failed to find map data with type #{map_type}; Meta: #{{framework: framework, module_name: module_name}}" unless found_map_data

          found_map_data
        end

        def identified_map_data(identifier, valid_types: ALL_TYPES)
          mtype = map_type(identifier)
          return unless valid_types.include?(mtype)

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

      # Mixin module used by Mapper to implement CIS-specific mapping behavior
      module MixinCIS
        def get_map(control_id, level: nil, profile: nil, **_)
          identified_map_data(control_id, valid_types: CIS_TYPES).get(control_id, level: level, profile: profile)
          return unless imdata

          if level.nil? || profile.nil?
            map_data[mtype][mtop].each do |lvl, profile_hash|
              next if lvl == 'benchmark' || (level && level != lvl)

              profile_hash.each do |prof, control_hash|
                next if profile && profile != prof

                return control_hash[control_id] if control_hash.key?(control_id)
              end
            end
          else
            imdata[level][profile][control_id]
          end
        end
      end

      # Mixin module used by Mapper to implement STIG-specific mapping behavior
      module MixinSTIG
        def get_map(control_id, level: nil, **_)
          mtype, mtop = map_type_and_top_key(control_id)
          return unless STIG_TYPES.include?(mtype)
          return map_data[mtype][mtop][level][control_id] unless level.nil?

          map_data[mtype][mtop].each do |lvl, control_hash|
            next if lvl == 'benchmark'

            return control_hash[control_id] if control_hash.key?(control_id)
          end
        end
      end
    end
  end
end
