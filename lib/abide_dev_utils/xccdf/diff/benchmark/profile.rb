# frozen_string_literal: true

require 'abide_dev_utils/xccdf/diff/benchmark/property_existence'

module AbideDevUtils
  module XCCDF
    module Diff
      # Diffs two sets of XCCDF profiles.
      class ProfileDiff
        def initialize(profiles, other_profiles)
          new_profile_rule_objs(profiles, other_profiles)
        end

        def diff_hash(diff_type, profile1, prof1_rules, profile2, prof2_rules)
          {

          }
        end

        private

        def new_profile_rule_objs(profiles, other_profiles)
          profile_objs = containers_from_profile_list(profiles)
          other_profile_objs = containers_from_profile_list(other_profiles)
          @self_prop_checker = PropertyExistenceChecker.new(profile_objs, other_profile_objs)
          @other_prop_checker = PropertyExistenceChecker.new(other_profile_objs, profile_objs)
          profile_objs.map { |p| p.prop_checker = @self_prop_checker }
          other_profile_objs.map { |p| p.prop_checker = @other_prop_checker }
          @profile_rule_objs = profile_objs
          @other_profile_rule_objs = other_profile_objs
        end

        def containers_from_profile_list(profile_list)
          profile_list.each_with_object([]) do |profile, ary|
            ary << ProfileRuleContainer.new(profile)
          end
        end
      end

      # Checks property existence in both profiles.
      class PropChecker < AbideDevUtils::XCCDF::Diff::Benchmark::PropertyExistence
        def initialize(profile_rule_objs, other_profile_rule_objs)
          super
          @profile_rule_objs = profile_rule_objs
          @other_profile_rule_objs = other_profile_rule_objs
          @profiles = profile_rule_objs.map(&:profile)
          @other_profiles = other_profile_rule_objs.map(&:profile)
        end

        def profile(profile)
          profile_key = profile.respond_to?(:id) ? profile.id : profile
          property_existence(profile_key, @profiles, @other_profiles)
        end

        def rule_in_profile(rule, profile, rule_key: :title)
          rk = rule.respond_to?(rule_key) ? rule.send(rule_key) : rule
          rules = @profiles.find { |p| p.id == profile }.linked_rule.map(&rk)
          other_rules = @other_profiles.find { |p| p.id == profile }.linked_rule.map(&rk)
          property_existence(rk, rules, other_rules)
        end

        def added_profiles
          added(@other_profiles.map(&:id), @profiles.map(&:id))
        end

        def removed_profiles
          removed(@profiles.map(&:id), @other_profiles.map(&:id))
        end

        def added_rules_by_profile
          @rules_by_profile.each_with_object({}) do |(profile, rules), hsh|
            next unless @other_rules_by_profile.key?(profile)

            hsh[profile] = added(rules, @other_rules_by_profile[profile])
          end
        end

        def removed_rules_by_profile
          @rules_by_profile.each_with_object({}) do |(profile, rules), hsh|
            next unless @other_rules_by_profile.key?(profile)

            hsh[profile] = removed(rules, @other_rules_by_profile[profile])
          end
        end
      end

      class ProfileRuleContainer
        include ::Comparable
        attr_accessor :prop_checker
        attr_reader :profile, :rules

        def initialize(profile, prop_checker = nil)
          @profile = profile
          @rules = profile.linked_rule
          @prop_checker = prop_checker
        end

        def <=>(other)
          @profile.id <=> other.profile.id
        end
      end
    end
  end
end
