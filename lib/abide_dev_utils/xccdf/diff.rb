# frozen_string_literal: true

require 'hashdiff'

module AbideDevUtils
  module XCCDF
    # Contains methods and classes used to diff XCCDF-derived objects.
    module Diff
      # Represents a change in a diff.
      class ChangeSet
        attr_reader :change, :key, :value, :value_to

        def initialize(change:, key:, value:, value_to: nil)
          validate_change(change)
          @change = change
          @key = key
          @value = value
          @value_to = value_to
        end

        def to_s
          val_to_str = value_to.nil? ? ' ' : " to #{value_to} "
          "#{change_string} value #{value}#{val_to_str}at #{key}"
        end

        def can_merge?(other)
          return false unless (change == '-' && other.change == '+') || (change == '+' && other.change == '-')
          return false unless key == other.key || value_hash_equality(other)

          true
        end

        def merge(other)
          unless can_merge?(other)
            raise ArgumentError, 'Cannot merge. Possible causes: change is identical; key or value do not match'
          end

          new_to_value = value == other.value ? nil : other.value
          ChangeSet.new(
            change: '~',
            key: key,
            value: value,
            value_to: new_to_value
          )
        end

        def merge!(other)
          new_props = merge(other)
          @change = new_props.change
          @key = new_props.key
          @value = new_props.value
          @value_to = new_props.value_to
        end

        private

        def value_hash_equality(other)
          equality = false
          value.each do |k, v|
            equality = true if v == other.value[k]
          end
          equality
        end

        def validate_change(change)
          raise ArgumentError, "Change type #{change} in invalid" unless ['+', '-', '~'].include?(change)
        end

        def change_string
          case change
          when '-'
            'remove'
          when '+'
            'add'
          else
            'change'
          end
        end
      end

      # Class used to diff two Benchmark profiles.
      class ProfileDiff
        DEFAULT_DIFF_OPTS = {
          similarity: 1,
          strict: true,
          strip: true,
          array_path: true,
          delimiter: '//',
          use_lcs: false
        }.freeze

        def initialize(profile_a, profile_b, opts = {})
          @profile_a = profile_a
          @profile_b = profile_b
          @opts = opts
        end

        def diff
          @diff ||= new_diff
        end

        private

        def new_diff
          Hashdiff.diff(profile_a, profile_b, DEFAULT_DIFF_OPTS).each_with_object({}) do |change, diff|
            val_to = change.length == 4 ? change[3] : nil
            change_key = change[2].is_a?(Hash) ? change[2][:title] : change[2]
            diff[change_key] = [] unless diff.key?(change_key)
            diff[change_key] << ChangeSet.new(change: change[0], key: change[1], value: change[2], value_to: val_to)
          end
        end
      end

      # Class used to diff two AbideDevUtils::XCCDF::Benchmark objects.
      class BenchmarkDiff
        DEFAULT_DIFF_OPTS = {
          similarity: 1,
          strict: true,
          strip: true,
          array_path: true,
          delimiter: '//',
          use_lcs: false
        }.freeze

        def initialize(benchmark_a, benchmark_b, opts = {})
          @benchmark_a = benchmark_a
          @benchmark_b = benchmark_b
          @opts = opts
        end

        def properties_to_diff
          @properties_to_diff ||= %i[title version profiles]
        end

        def title_version
          @title_version ||= diff_title_version
        end

        def profiles
          @profiles ||= diff_profiles
        end

        private

        def diff_title_version
          Hashdiff.diff(
            @benchmark_a.to_h.reject { |k, _| k.to_s == 'profiles' },
            @benchmark_b.to_h.reject { |k, _| k.to_s == 'profiles' },
            DEFAULT_DIFF_OPTS
          )
        end

        def diff_profiles(profile: nil)
          diff = {}
          other_hash = @benchmark_b.to_h[:profiles]
          @benchmark_a.to_h[:profiles].each do |name, data|
            next if profile && profile != name

            diff[name] = ProfileDiff.new(data, other_hash[name], @opts).diff
          end
          diff
        end
      end

      def self.diff_benchmarks(benchmark_a, benchmark_b, opts = {})
        profile = opts.fetch(:profile, nil)
        profile_key = profile.nil? ? 'all_profiles' : profile
        benchmark_diff = BenchmarkDiff.new(benchmark_a, benchmark_b, opts)
        diff = if profile.nil?
                 benchmark_diff.diff_profiles.each do |_, v|
                   v.transform_values! { |x| x.map!(&:to_s) }
                 end
               else
                 benchmark_diff.diff_profiles(profile: profile)[profile].transform_values! { |x| x.map!(&:to_s) }
               end
        {
          'benchmark' => benchmark_diff.diff_title_version,
          profile_key => diff,
        }
      end
    end
  end
end
