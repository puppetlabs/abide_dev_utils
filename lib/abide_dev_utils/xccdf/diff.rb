# frozen_string_literal: true

require 'hashdiff'

module AbideDevUtils
  module XCCDF
    # Contains methods and classes used to diff XCCDF-derived objects.
    module Diff
      DEFAULT_DIFF_OPTS = {
        similarity: 1,
        strict: true,
        strip: true,
        array_path: true,
        delimiter: '//',
        use_lcs: true,
      }.freeze

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
          value_change_string(value, value_to)
        end

        def to_h
          {
            change: change,
            key: key,
            value: value,
            value_to: value_to,
          }
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

        def validate_change(chng)
          raise ArgumentError, "Change type #{chng} in invalid" unless ['+', '-', '~'].include?(chng)
        end

        def change_string(chng)
          case chng
          when '-'
            'Remove'
          when '+'
            'Add'
          else
            'Change'
          end
        end

        def value_change_string(value, value_to)
          change_str = []
          change_diff = Hashdiff.diff(value, value_to || {}, AbideDevUtils::XCCDF::Diff::DEFAULT_DIFF_OPTS)
          return if change_diff.empty?
          return value_change_string_single_type(change_diff, value) if all_single_change_type?(change_diff)

          change_diff.each do |chng|
            change_str << if chng.length == 4
                            "#{change_string(chng[0])} #{chng[1][0]} \"#{chng[2]}\" to \"#{chng[3]}\""
                          else
                            "#{change_string(chng[0])} #{chng[1][0]} with value #{chng[2]}"
                          end
          end
          change_str.join(', ')
        end

        def value_change_string_single_type(change_diff, value)
          "#{change_string(change_diff[0][0])} #{value[:number]} - #{value[:level]} - #{value[:title]}"
        end

        def all_single_change_type?(change_diff)
          change_diff.length > 1 && change_diff.map { |x| x[0] }.uniq.length == 1
        end
      end

      # Class used to diff two Benchmark profiles.
      class ProfileDiff
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
          Hashdiff.diff(@profile_a, @profile_b, AbideDevUtils::XCCDF::Diff::DEFAULT_DIFF_OPTS).each_with_object({}) do |change, diff|
            val_to = change.length == 4 ? change[3] : nil
            change_key = change[2].is_a?(Hash) ? change[2][:title] : change[2]
            if diff.key?(change_key)
              diff[change_key] = merge_changes(
                [
                  diff[change_key][0],
                  ChangeSet.new(change: change[0], key: change[1], value: change[2], value_to: val_to),
                ]
              )
            else
              diff[change_key] = [ChangeSet.new(change: change[0], key: change[1], value: change[2], value_to: val_to)]
            end
          end
        end

        def merge_changes(changes)
          return changes if changes.length < 2

          if changes[0].can_merge?(changes[1])
            [changes[0].merge(changes[1])]
          else
            changes
          end
        end
      end

      # Class used to diff two AbideDevUtils::XCCDF::Benchmark objects.
      class BenchmarkDiff
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

        def profiles(profile: nil)
          @profiles ||= diff_profiles(profile: profile)
        end

        private

        def diff_title_version
          diff = Hashdiff.diff(
            @benchmark_a.to_h.reject { |k, _| k.to_s == 'profiles' },
            @benchmark_b.to_h.reject { |k, _| k.to_s == 'profiles' },
            AbideDevUtils::XCCDF::Diff::DEFAULT_DIFF_OPTS
          )
          diff.each_with_object({}) do |change, tdiff|
            val_to = change.length == 4 ? change[3] : nil
            change_key = change[2].is_a?(Hash) ? change[2][:title] : change[2]
            tdiff[change_key] = [] unless tdiff.key?(change_key)
            tdiff[change_key] << ChangeSet.new(change: change[0], key: change[1], value: change[2], value_to: val_to)
          end
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
        transform_method_sym = opts.fetch(:raw, false) ? :to_h : :to_s
        diff = if profile.nil?
                 benchmark_diff.profiles.each do |_, v|
                   v.transform_values! { |x| x.map!(&transform_method_sym) }
                 end
               else
                 benchmark_diff.profiles(profile: profile)[profile].transform_values! { |x| x.map!(&transform_method_sym) }
               end
        return diff.values.flatten if opts.fetch(:raw, false)

        {
          'benchmark' => benchmark_diff.title_version.transform_values { |x| x.map!(&:to_s) },
          profile_key => diff.values.flatten,
        }
      end
    end
  end
end
