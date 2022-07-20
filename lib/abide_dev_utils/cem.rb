# frozen_string_literal: true

require 'abide_dev_utils/xccdf'
require 'abide_dev_utils/cem/coverage_report'
require 'abide_dev_utils/cem/generate'

module AbideDevUtils
  # Methods for working with Compliance Enforcement Modules (CEM)
  module CEM
    def self.xccdf
      return @xccdf if defined?(@xccdf)

      xccdf = Object.new
      xccdf.extend AbideDevUtils::XCCDF::Common
      @xccdf = xccdf
      @xccdf
    end

    def self.rule_id_format(rule_id)
      case rule_id
      when /^c[0-9_]+$/
        :hiera_title_num
      when /^[a-z][a-z0-9_]+$/
        :hiera_title
      when /^[0-9.]+$/
        :number
      else
        :title
      end
    end

    def self.rule_identifiers(rule_id)
      {
        number: xccdf.control_parts(rule_id).first,
        hiera_title: xccdf.name_normalize_control(rule_id),
        hiera_title_num: xccdf.number_normalize_control(rule_id),
      }
    end

    def self.update_legacy_config_from_diff(config_hiera, diff)
      new_config_hiera = config_hiera.dup
      new_control_configs = {}
      change_report = []
      changes = diff.select { |d| d[:type][0] == :number }
      config_hiera['config']['control_configs'].each do |key, val_hash|
        key_id_format = rule_id_format(key)
        changed = false
        changes.each do |change|
          if key_id_format == :title
            next unless change[:title] == key
          else
            next unless rule_identifiers(change[:self].id)[key_id_format] == key
          end

          changed = true
          new_key = if key_id_format == :title
                      change[:other_title]
                    else
                      rule_identifiers(change[:other].id)[key_id_format]
                    end
          new_control_configs[new_key] = val_hash
          change_report << {
            type: :identifier_update,
            from: key,
            to: new_key,
          }
        end
        new_control_configs[key] = val_hash unless changed
      end
      new_config_hiera['config']['control_configs'] = new_control_configs
      [new_config_hiera, change_report]
    end
  end
end
