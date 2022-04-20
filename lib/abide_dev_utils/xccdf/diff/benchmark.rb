# frozen_string_literal: true

require 'abide_dev_utils/xccdf/diff/benchmark/number_title'
require 'abide_dev_utils/xccdf/diff/benchmark/property'
require 'abide_dev_utils/xccdf/diff/utils'
require 'abide_dev_utils/xccdf/parser'

module AbideDevUtils
  module XCCDF
    # Holds methods and classes used to diff XCCDF-derived objects.
    module Diff
      # Class for benchmark diffs
      class BenchmarkDiff
        include AbideDevUtils::XCCDF::Diff::BenchmarkPropertyDiff
        attr_reader :self, :other, :opts

        DEFAULT_OPTS = {
          only_classes: %w[rule],
        }.freeze

        # Used for filtering by level and profile
        LVL_PROF_DEFAULT = [nil, nil].freeze

        # @param xml1 [String] path to the first benchmark XCCDF xml file
        # @param xml2 [String] path to the second benchmark XCCDF xml file
        # @param opts [Hash] options hash
        def initialize(xml1, xml2, opts = {})
          @self = new_benchmark(xml1)
          @other = new_benchmark(xml2)
          @opts = DEFAULT_OPTS.merge(DEFAULT_PROPERTY_DIFF_OPTS).merge(opts)
          @levels = []
          @profiles = []
        end

        def method_missing(method_name, *args, &block)
          if opts.key?(method_name)
            opts[method_name]
          elsif @diff&.key?(method_name)
            @diff[method_name]
          else
            super
          end
        end

        def respond_to_missing?(method_name, include_private = false)
          opts.key?(method_name) || @diff&.key?(method_name) || super
        end

        # Memoized getter for all "numbered" children for the "self" benchmark based on optional filters in opts
        def self_numbered_children
          @self_numbered_children ||= find_all_numbered_children(@self,
                                                                 only_classes: opts[:only_classes],
                                                                 level: opts[:level],
                                                                 profile: opts[:profile])
        end

        # Memoized getter for all "numbered" children for the "other" benchmark based on optional filters in opts
        def other_numbered_children
          @other_numbered_children ||= find_all_numbered_children(@other,
                                                                  only_classes: opts[:only_classes],
                                                                  level: opts[:level],
                                                                  profile: opts[:profile])
        end

        # Basic title diff
        def numbered_children_title_diff
          {
            self: self_numbered_children.map { |c| c.title.to_s } - other_numbered_children.map { |c| c.title.to_s },
            other: other_numbered_children.map { |c| c.title.to_s } - self_numbered_children.map { |c| c.title.to_s },
          }
        end

        # Returns the output of a NumberTitleDiff object's diff function based on self_numbered_children and other_numbered_children
        def number_title_diff
          NumberTitleDiff.new(self_numbered_children, other_numbered_children).diff
        end

        # Hash of data about the "self" benchmark and the diff parameters
        def from_benchmark
          @from_benchmark ||= from_to_hash(@self)
        end

        # Hash of data about the "other" benchmark and the diff parameters
        def to_benchmark
          @to_benchmark ||= from_to_hash(@other)
        end

        # All levels that numbered children have been filtered on
        def levels
          @levels.flatten.uniq.empty? ? [:all] : @levels.flatten.uniq
        end

        # All profiles that numbered children have been filtered on
        def profiles
          @profiles.flatten.uniq.empty? ? [:all] : @profiles.flatten.uniq
        end

        # Returns a diff of the changes from the "self" xml (xml1) to the "other" xml (xml2)
        # This function is memoized because the diff operation is expensive. To run the diff
        # operation again, set the `new` parameter to `true`
        # @param new [Boolean] Set to `true` to force a new diff operation
        # return [Hash] the diff in hash format
        def diff(new: false)
          return @diff if @diff && !new

          @diff = {}
          @diff[:number_title] = number_title_diff
          { from: from_benchmark, to: to_benchmark, diff: @diff }
        end

        private

        # Returns a Benchmark object from a XCCDF xml file path
        # @param xml [String] path to a XCCDF xml file
        def new_benchmark(xml)
          AbideDevUtils::XCCDF::Parser.parse(xml)
        end

        # Returns a hash of benchmark data
        # @param obj [AbideDevUtils::XCCDF::Parser::Objects::Benchmark]
        # @return [Hash] diff-relevant benchmark information
        def from_to_hash(obj)
          {
            title: obj.title.to_s,
            version: obj.version.to_s,
            compared: {
              levels: levels,
              profiles: profiles,
            }
          }
        end

        # Function to check if a numbered child meets inclusion criteria based on filtering
        # options.
        # @param child [Object] XCCDF parser object that includes AbideDevUtils::XCCDF::Parser::Objects::NumberedObject.
        # @param only_classes [Array] class names as strings. When this is specified, only objects with those class names will be considered.
        # @param level [String] Specifies the benchmark profile level to filter children on. Only applies to Rules linked to Profiles that have levels.
        # @param profile [String] Specifies the benchmark profile to filter children on. Only applies to Rules that have linked Profiles.
        # @return [TrueClass] if child meets all filtering criteria and should be included in the set.
        # @return [FalseClass] if child does not meet all criteria and should be excluded from the set.
        def include_numbered_child?(child, only_classes: [], level: nil, profile: nil)
          return false unless valid_class?(child, only_classes)
          return true if level.nil? && profile.nil?

          validated_props = valid_profile_and_level(child, level, profile)
          should_include = validated_props.none?(&:nil?)
          new_validated_props_vars(validated_props) if should_include
          should_include
        end

        # Adds level and profile to respective instance vars
        # @param validated_props [Array] two item array: first item - profile level, second item - profile title
        def new_validated_props_vars(validated_props)
          @levels << validated_props[0]
          @profiles << validated_props[1]
        end

        # Checks if the child's class is in the only_classes list, if applicable
        # @param child [Object] the child whose class will be checked
        # @param only_classes [Array] an array of class names as strings
        # @return [TrueClass] if only_classes is empty or if child's class is in only_classes
        # @return [FalseClass] if only_classes is not empty and child's class is not in only_classes
        def valid_class?(child, only_classes = [])
          only_classes.empty? || only_classes.include?(child.label)
        end

        # Returns a two-item array of a valid level and a valid profile
        # @param child [Object] XCCDF parser object or array of XCCDF parser objects
        # @param level [String] a profile level
        # @param profile [String] a partial / full profile title
        # @return [Array] two-item array: first item - Profile level or nil, second item - Profile title or nil
        def valid_profile_and_level(child, level, profile)
          return LVL_PROF_DEFAULT unless child.respond_to?(:linked_profile)

          validate_profile_obj(child.linked_profile, level, profile)
        end

        # Returns array (or array of arrays) of valid level and valid profile based on child's linked profiles
        # @param obj [Object] AbideDevUtils::XCCDF::Parser::Objects::Profile objects or array of them
        # @param level [String] a profile level
        # @param profile [String] a partial / full profile title
        # @return [Array] two-item array: first item - Profile level or nil, second item - Profile title or nil
        # @return [Array] Array of two item arrays if `obj` is an array of profiles
        def validate_profile_obj(obj, level, profile)
          return LVL_PROF_DEFAULT if obj.nil?
          return validate_profile_objs(obj, level, profile) if obj.respond_to?(:each)

          validated_level = valid_level?(obj, level) ? obj.level : nil
          validated_profile = valid_profile?(obj, profile) ? obj.title.to_s : nil
          [validated_level, validated_profile]
        end

        # Returns array of arrays of valid levels and valid profiles based on all children's linked profiles
        # @param objs [Array] Array of AbideDevUtils::XCCDF::Parser::Objects::Profile objects
        # @param level [String] a profile level
        # @param profile [String] a partial / full profile title
        # @return [Array] Array of two-item arrays
        def validate_profile_objs(objs, level, profile)
          found = [LVL_PROF_DEFAULT]
          objs.each do |obj|
            validated = validate_profile_obj(obj, level, profile)
            next if validated.any?(&:nil?)

            found << validated
          end
          found
        end

        # Checks if a given object has a matching level. This is done
        # via a basic regex match on the object's #level method
        # @param obj [AbideDevUtils::XCCDF::Parser::Objects::Profile] the profile object
        # @param level [String] a level to check
        # @return [TrueClass] if level matches
        # @return [FalseClass] if level does not match
        def valid_level?(obj, level)
          return true if level.nil? || obj.level.nil?

          obj.level.match?(/#{Regexp.escape level}/i)
        end

        # Checks if a given profile object has a matching title or id. This
        # is done with a regex match against the profile's title as a string
        # or against it's object string representation (the ID).
        # @param obj [AbideDevUtils::XCCDF::Parser::Objects::Profile] the profile object
        # @param profile [String] a profile string to check
        # @return [TrueClass] if `profile` matches either the profile's title or ID
        # @return [FalseClass] if `profile` matches neither
        def valid_profile?(obj, profile)
          return true if profile.nil?

          obj.title.to_s.match?(/#{Regexp.escape profile}/i) ||
            obj.to_s.match?(/#{Regexp.escape profile}/i)
        end

        # Finds all children of the benchmark that implement AbideDevUtils::XCCDF::Parser::Objects::NumberedObject
        # that are not filtered out based on optional parameters. This method recursively walks down the hierarchy
        # of the benchmark to ensure that all deeply nested objects are accounted for.
        # @param benchmark [AbideDevUtils::XCCDF::Parser::Objects::Benchmark] the benchmark to check
        # @param only_classes [Array] An array of class names. Only children with the specified class names will be returned
        # @param level [String] A profile level. Only children that have linked profiles that match this level will be returned
        # @param profile [String] A profile title / id. Only children that have linked profiles that match this title / id will be returned
        # @param numbered_children [Array] An array of numbered children to check. If this is empty, we start checking at the top-level of
        #   the benchmark. To get all of the benchmark's numbered children, this should be an empty array when calling this method.
        # @return [Array] A sorted array of numbered children.
        def find_all_numbered_children(benchmark, only_classes: [], level: nil, profile: nil, numbered_children: [])
          benchmark.find_children_that_respond_to(:number).each do |child|
            numbered_children << child if include_numbered_child?(child,
                                                                  only_classes: only_classes,
                                                                  level: level,
                                                                  profile: profile)
            find_all_numbered_children(child,
                                       only_classes: only_classes,
                                       level: level,
                                       profile: profile,
                                       numbered_children: numbered_children)
          end
          numbered_children.sort
        end

        # Returns a subset of benchmark children based on a property of that child and search values
        def find_subset_of_children(children, property, search_values)
          children.select { |c| search_values.include?(c.send(property)) }
        end
      end
    end
  end
end
