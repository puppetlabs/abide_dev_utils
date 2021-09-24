# frozen_string_literal: true

require 'nokogiri'
require 'abide_dev_utils/validate'
require 'pry'

module AbideDevUtils
  module XCCDF
    module Utils
      CONTROL_PREFIX = /^[\d.]+_/.freeze
      UNDERSCORED = /(\s|\(|\)|-|\.)/.freeze
      CIS_NEXT_GEN_WINDOWS = /(next_generation_windows_security)/.freeze
      CIS_XPATHS = {
        benchmark: {
          all: 'xccdf:Benchmark',
          title: 'xccdf:Benchmark/xccdf:title',
          version: 'xccdf:Benchmark/xccdf:version'
        },
        profiles: {
          all: 'xccdf:Benchmark/xccdf:Profile',
          relative_title: './xccdf:title',
          relative_select: './xccdf:select'
        }
      }.freeze

      def parse(xccdf_file)
        AbideDevUtils::Validate.file(xccdf_file)
        File.open(xccdf_file) { |f| Nokogiri::XML(f) }
      end

      def normalize_string(str)
        nstr = str.downcase
        nstr.gsub!(/[^a-z0-9]$/, '')
        nstr.gsub!(/^[^a-z]/, '')
        nstr.gsub!(/^(l1_|l2_|ng_)/, '')
        nstr.delete!('(/|\\|\+)')
        nstr.gsub!(UNDERSCORED, '_')
        nstr.strip!
        nstr
      end

      def normalize_profile_name(prof)
        prof_name = normalize_string("profile_#{prof}")
        prof_name.gsub!(NEXT_GEN_WINDOWS, 'ngws')
        prof_name.strip!
        prof_name
      end

      def normalize_control_name(control, number_format: false)
        return number_normalize_control(control) if number_format

        name_normalize_control(control)
      end

      def name_normalize_control(control)
        new_ctrl = control.split('benchmarks_rule_')[-1].gsub(CONTROL_PREFIX, '')
        normalize_string(new_ctrl)
      end

      def number_normalize_control(control)
        part = control.split('benchmarks_rule_')[-1]
        numpart = CONTROL_PREFIX.match(part).to_s.chop.gsub(UNDERSCORED, '_')
        "c#{numpart}"
      end

      def text_normalize_control(control)
        control = control['idref'].to_s unless control.respond_to?(:split)

        control.split('benchmarks_rule_')[-1].tr('_', ' ')
      end

      def all_cis_recommendations(parsed_xccdf)
        parsed_xccdf.xpath('//xccdf:select').uniq
      end

      def find_cis_recommendation(name, recommendations, number_format: false)
        recommendations.each do |reco|
          if normalize_control_name(reco['idref'].to_s, number_format: number_format) == name
            return text_normalize_control(reco['idref'].to_s)
          end
        end
      end
    end
  end
end
