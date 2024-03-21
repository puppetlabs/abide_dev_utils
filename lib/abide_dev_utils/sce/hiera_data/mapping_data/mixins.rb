# frozen_string_literal: true

module AbideDevUtils
  module Sce
    module HieraData
      module MappingData
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
end
