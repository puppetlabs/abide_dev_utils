# frozen_string_literal: true

require_relative 'parser'

module AbideDevUtils
  module XCCDF
    # Contains methods and classes used to diff XCCDF-derived objects.
    module Diff
      def self.benchmark_diff(xml1, xml2, opts = {})
        bd = BenchmarkDiff.new(xml1, xml2, opts)
        if opts[:raw]
          return bd.diff_rules_raw if opts[:rules_only]

          bd.diff_raw
        else
          return bd.diff_rules if opts[:rules_only]

          bd.diff
        end
      end

      # Class for benchmark diffs
      class BenchmarkDiff
        attr_reader :this, :other, :opts

        # @param xml1 [String] path to the first benchmark XCCDF xml file
        # @param xml2 [String] path to the second benchmark XCCDF xml file
        # @param opts [Hash] options hash
        def initialize(xml1, xml2, opts = {})
          @this = new_benchmark(xml1)
          @other = new_benchmark(xml2)
          @opts = opts
        end

        def diff_raw
          @diff_raw ||= @this.diff(@other)
        end

        def diff
          warn 'Full benchmark diff is not yet implemented, return rules diff for now'
          diff_rules
        end

        def diff_rules_raw
          @diff_rules_raw ||= @this.diff_only_rules(@other)
        end

        def diff_rules
          return diff_rules_raw if opts[:raw]
          return [] if diff_rules_raw.all? { |r| r.type == :equal }

          diff_hash = {
            from: @this.to_s,
            to: @other.to_s,
            rules: {}
          }
          diff_rules_raw.each do |rule|
            diff_hash[:rules][rule.type] ||= []
            case rule.type
            when :added
              diff_hash[:rules][rule.type] << { number: rule.new_value.number.to_s, title: rule.new_value.title.to_s }
            when :removed
              diff_hash[:rules][rule.type] << { number: rule.old_value.number.to_s, title: rule.old_value.title.to_s }
            else
              rd_hash = {}
              rd_hash[:from] = "#{rule.old_value&.number} #{rule.old_value&.title}" if rule.old_value
              rd_hash[:to] = "#{rule.new_value&.number} #{rule.new_value&.title}" if rule.new_value
              changes = rule.details.transform_values { |v| v.is_a?(Array) ? v.map(&:to_s) : v.to_s }
              if opts[:ignore_changed_properties]
                changes.delete_if { |k, _| opts[:ignore_changed_properties].include?(k.to_s) }
                next if changes.empty? # Skip entirely if all changed filtered out
              end
              rd_hash[:changes] = changes unless changes.empty?
              diff_hash[:rules][rule.type] << rd_hash
            end
          end
          unless opts[:no_stats]
            stats_hash = {}
            diff_hash[:rules].each do |type, rules|
              stats_hash[type] = rules.size
            end
            diff_hash[:stats] = stats_hash unless stats_hash.empty?
          end
          diff_hash
        end

        private

        # Returns a Benchmark object from a XCCDF xml file path
        # @param xml [String] path to a XCCDF xml file
        def new_benchmark(xml)
          AbideDevUtils::XCCDF::Parser.parse(xml)
        end
      end
    end
  end
end
