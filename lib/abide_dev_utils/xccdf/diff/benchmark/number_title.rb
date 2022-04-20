# frozen_string_literal: true

require 'abide_dev_utils/xccdf/diff/benchmark/property_existence'

module AbideDevUtils
  module XCCDF
    module Diff
      # Diffs two XCCDF benchmarks using the title / number of the items as the primary
      # diff properties.
      class NumberTitleDiff
        SKIP_DIFF_TYPES = %i[equal both].freeze

        def initialize(numbered_children, other_numbered_children)
          new_number_title_objs(numbered_children, other_numbered_children)
        end

        def diff
          @diff ||= find_diffs(@number_title_objs, @other_number_title_objs)
        end

        def to_s
          parts = []
          @diff.each do |_, diffs|
            diffs.each do |dh|
              parts << dh[:diff_text]
            end
          end
          parts.join("\n")
        end

        private

        attr_writer :diff

        def added_number_title_objs
          added_titles = @self_prop_checker.added_titles
          @other_number_title_objs.select do |nto|
            added_titles.include?(nto.title)
          end
        end

        def removed_number_title_objs
          removed_titles = @self_prop_checker.removed_titles
          @number_title_objs.select do |nto|
            removed_titles.include?(nto.title)
          end
        end

        def find_diffs(objs, other_objs)
          diffs = []
          added_number_title_objs.each do |nto|
            change_type = %i[both added]
            stand_in = NumberTitleContainerStandIn.new(change_type)
            diffs << process_diffs([diff_hash(change_type, stand_in, nto)])
          end
          removed_number_title_objs.each do |nto|
            change_type = %i[both removed]
            stand_in = NumberTitleContainerStandIn.new(change_type)
            diffs << process_diffs([diff_hash(change_type, nto, stand_in)])
          end
          objs.each do |obj|
            obj_diffs = other_objs.each_with_object([]) do |other_obj, o_ary|
              obj_diff = obj.diff(other_obj)
              next if SKIP_DIFF_TYPES.include?(obj_diff[0])

              o_ary << diff_hash(obj_diff, obj, other_obj)
            end

            processed_obj_diffs = process_diffs(obj_diffs)
            diffs << processed_obj_diffs unless obj_diffs.empty?
          end
          diffs
        end

        def process_diffs(diffs)
          return {} if diffs.empty?

          raise "Unexpected diffs: #{diffs}" if diffs.length > 2

          return diffs[0] if diffs.length == 1

          if diffs[0][:type][0] == PropChecker.inverse_existence_state[diffs[1][:type][0]]
            diffs[0]
          else
            diffs[1]
          end
        end

        def diff_hash(diff_type, obj, other_obj)
          {
            self: obj.child,
            other: other_obj.child,
            type: diff_type,
            text: diff_type_text(diff_type, obj, other_obj),
            number: obj.number,
            other_number: other_obj.number,
            title: obj.title,
            other_title: other_obj.title,
          }
        end

        def diff_type_text(diff_type, obj, other_obj)
          DiffTypeText.text(diff_type, obj, other_obj)
        end

        def new_number_title_objs(children, other_children)
          number_title_objs = children.map { |c| NumberTitleContainer.new(c) }.sort
          other_number_title_objs = other_children.map { |c| NumberTitleContainer.new(c) }.sort
          @self_prop_checker = PropChecker.new(number_title_objs, other_number_title_objs)
          @other_prop_checker = PropChecker.new(other_number_title_objs, number_title_objs)
          number_title_objs.map { |n| n.prop_checker = @self_prop_checker }
          other_number_title_objs.map { |n| n.prop_checker = @other_prop_checker }
          @number_title_objs = number_title_objs
          @other_number_title_objs = other_number_title_objs
        end
      end

      # Creates string representations of diff types
      class DiffTypeText
        def self.text(diff_type, obj, other_obj)
          case diff_type[0]
          when :equal
            'The objects are equal'
          when :title
            "Title changed: Number \"#{obj.number}\": #{obj.title} -> #{other_obj.title}"
          when :number
            number_diff_type_text(diff_type, obj, other_obj)
          when :both
            both_diff_type_text(diff_type, obj, other_obj)
          when :add
            "Add object with number \"#{other_obj.number}\" and title \"#{other_obj.title}\""
          when :remove
            "Remove object with number \"#{obj.number}\" and title \"#{obj.title}\""
          else
            raise ArgumentError, "Unknown diff type: #{diff_type}"
          end
        end

        def self.number_diff_type_text(diff_type, obj, other_obj)
          case diff_type[1]
          when :added
            "Number changed (New Number): Title \"#{obj.title}\": #{obj.number} -> #{other_obj.number}"
          when :exists
            "Number changed (Existing Number): Title \"#{obj.title}\": #{obj.number} -> #{other_obj.number}"
          else
            raise ArgumentError, "Unknown diff type for number change: #{diff_type[1]}"
          end
        end

        def self.both_diff_type_text(diff_type, obj, other_obj)
          case diff_type[1]
          when :added
            "Added object: Title \"#{other_obj.title}\": Number \"#{other_obj.number}\""
          when :removed
            "Removed object: Title \"#{obj.title}\": Number \"#{obj.number}\""
          else
            raise ArgumentError, "Unknown diff type for both change: #{diff_type[1]}"
          end
        end
      end

      # Checks properties for existence in both benchmarks.
      class PropChecker < AbideDevUtils::XCCDF::Diff::PropertyExistenceChecker
        attr_reader :all_numbers, :all_titles, :other_all_numbers, :other_all_titles

        def initialize(number_title_objs, other_number_title_objs)
          super
          @all_numbers = number_title_objs.map(&:number)
          @all_titles = number_title_objs.map(&:title)
          @other_all_numbers = other_number_title_objs.map(&:number)
          @other_all_titles = other_number_title_objs.map(&:title)
        end

        def title(title)
          property_existence(title, @all_titles, @other_all_titles)
        end

        def number(number)
          property_existence(number, @all_numbers, @other_all_numbers)
        end

        def added_numbers
          added(@all_numbers, @other_all_numbers)
        end

        def removed_numbers
          removed(@all_numbers, @other_all_numbers)
        end

        def added_titles
          added(@all_titles, @other_all_titles)
        end

        def removed_titles
          removed(@all_titles, @other_all_titles)
        end
      end

      class NumberTitleDiffError < StandardError; end
      class InconsistentDiffTypeError < StandardError; end

      # Holds a number and title for a child of a benchmark
      # and provides methods to compare it to another child.
      class NumberTitleContainer
        include ::Comparable
        attr_accessor :prop_checker
        attr_reader :child, :number, :title

        def initialize(child, prop_checker = nil)
          @child = child
          @number = child.number.to_s
          @title = child.title.to_s
          @prop_checker = prop_checker
        end

        def diff(other)
          return %i[equal exist] if number == other.number && title == other.title

          if number == other.number && title != other.title
            c_diff = correlate_prop_diff_types(@prop_checker.title(other.title),
                                               other.prop_checker.title(other.title))
            [:title, c_diff]
          elsif title == other.title && number != other.number
            c_diff = correlate_prop_diff_types(@prop_checker.number(other.number),
                                               other.prop_checker.number(other.number))
            [:number, c_diff]
          else
            %i[both exist]
          end
        rescue StandardError => e
          err_str = [
            'Error diffing number and title',
            "Number: #{number}",
            "Title: #{title}",
            "Other number: #{other.number}",
            "Other title: #{other.title}",
            e.message,
          ]
          raise NumberTitleDiffError, err_str.join(', ')
        end

        def <=>(other)
          child <=> other.child
        end

        private

        def correlate_prop_diff_types(self_type, other_type)
          inverse_diff_type = PropChecker.inverse_existence_state[self_type]
          return other_type if inverse_diff_type.nil?

          self_type
        end
      end

      # Stand-in object for a NumberTitleContainer when the NumberTitleContainer
      # would not exist. This is used when a change is an add or remove.
      class NumberTitleContainerStandIn
        attr_reader :child, :number, :title

        def initialize(change_type)
          @change_type = change_type
          @child = nil
          @number = ''
          @title = ''
        end
      end
    end
  end
end
