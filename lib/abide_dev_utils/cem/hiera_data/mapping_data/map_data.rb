# frozen_string_literal: true

module AbideDevUtils
  module CEM
    module HieraData
      module MappingData
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
      end
    end
  end
end
