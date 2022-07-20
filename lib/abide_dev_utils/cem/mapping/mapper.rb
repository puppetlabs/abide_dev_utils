# frozen_string_literal: true

module AbideDevUtils
  module CEM
    module Mapping
      # Handles interacting with mapping data
      class Mapper
        MAP_TYPES = %w[hiera_title_num number hiera_title vulnid title].freeze

        attr_reader :module_name, :framework, :map_data

        def initialize(module_name, framework, map_data)
          @module_name = module_name
          @framework = framework
          load_framework(@framework)
          @map_data = map_data
          @cache = {}
          @rule_cache = {}
        end

        def title
          @title ||= benchmark_data['title']
        end

        def version
          @version ||= benchmark_data['version']
        end

        def each_like(identifier)
          mtype, mtop = map_type_and_top_key(identifier)
          map_data[mtype][mtop].each { |key, val| yield key, val }
        end

        def each_with_array_like(identifier)
          mtype, mtop = map_type_and_top_key(identifier)
          map_data[mtype][mtop].each_with_object([]) { |(key, val), ary| yield [key, val], ary }
        end

        def get(control_id, level: nil, profile: nil)
          return cache_get(control_id, level, profile) if cached?(control_id, level, profile)

          value = get_map(control_id, level: level, profile: profile)
          return if value.nil? || value.empty?

          cache_set(value, control_id, level, profile)
          value
        end

        def map_type(control_id)
          return control_id if MAP_TYPES.include?(control_id)

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

        def map_type_and_top_key(identifier)
          mtype = MAP_TYPES.include?(identifier) ? identifier : map_type(identifier)
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
          @default_map_type ||= (framework == 'stig' ? 'vulnid' : map_data.keys.first)
        end

        def benchmark_data
          @benchmark_data ||= map_data[default_map_type][map_top_key(default_map_type)]['benchmark']
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
          mtype, mtop = map_type_and_top_key(control_id)
          return if mtype == 'vulnid'

          return map_data[mtype][mtop][level][profile][control_id] unless level.nil? || profile.nil?

          map_data[mtype][mtop].each do |lvl, profile_hash|
            next if lvl == 'benchmark'

            profile_hash.each do |prof, control_hash|
              return map_data[mtype][mtop][lvl][prof][control_id] if control_hash.key?(control_id)
            end
          end
        end
      end

      # Mixin module used by Mapper to implement STIG-specific mapping behavior
      module MixinSTIG
        def get_map(control_id, level: nil, **_)
          mtype, mtop = map_type_and_top_key(control_id)
          return map_data[mtype][mtop][level][control_id] unless level.nil?

          begin
            map_data[mtype][mtop].each do |lvl, control_hash|
              next if lvl == 'benchmark'

              return control_hash[control_id] if control_hash.key?(control_id)
            end
          rescue NoMethodError => e
            require 'pry'
            binding.pry
            #raise "Control ID: #{control_id}, Level: #{level}, #{e.message}"
          end
        end
      end
    end
  end
end
