# frozen_string_literal: true

module AbideDevUtils
  module XCCDF
    module Parser
      module Objects
        # Methods for converting an object to a hash
        module DiffableObject
          # Generic error class for diffable objects
          class DiffableObjectError < StandardError
            def initialize(self_obj = nil, other_obj = nil, custom_msg: nil)
              if custom_msg.nil?
                super("This object (#{self_obj}) is not diffable with other object (#{other_obj})")
              else
                super(custom_msg)
              end
              @self_obj = self_obj
              @other_obj = other_obj
              @custom_msg = custom_msg
            end
          end

          # Raised when the diffed objects are not instances of the same class
          class NotSameClassError < DiffableObjectError
            def initialize(self_obj = nil, other_obj = nil)
              super(
                self_obj,
                other_obj,
                custom_msg: "This object's class (#{self_obj.class}) does not match other object's class (#{other_obj.class})",
              )
            end
          end

          # Holds the result of a diff on a per-item basis.
          class DiffChangeResult
            attr_accessor :type, :details
            attr_reader :old_value, :new_value, :element

            def initialize(type, old_value, new_value, element, details = {})
              @type = type
              @old_value = old_value
              @new_value = new_value
              @element = element
              @details = details
            end

            def to_h(hash_objs: false)
              return new_hash(type, old_value, new_value, element, details) unless hash_objs

              old_val = old_value.respond_to?(:to_s) ? old_value.to_s : old_value.inspect
              new_val = new_value.respond_to?(:to_s) ? new_value.to_s : new_value.inspect
              details_hash = details.transform_values do |val|
                case val
                when DiffChangeResult
                  val.to_h(hash_objs: hash_objs)
                when Array
                  val.map { |v| v.is_a?(DiffChangeResult) ? v.to_h(hash_objs: hash_objs) : v.to_s }
                else
                  val.to_s
                end
              end
              new_hash(type, old_val, new_val, element, details_hash)
            end

            def to_yaml
              require 'yaml'
              to_h(hash_objs: true).to_yaml
            end

            def to_a
              [type, old_value, new_value, element, details]
            end

            def to_s
              "#{element} #{type}: #{old_value} -> #{new_value}, #{details}"
            end

            private

            def new_hash(change_type, old_val, new_val, element, details_hash)
              hsh = {}
              hsh[:type] = change_type
              hsh[:old_value] = old_val unless old_val.nil? || (old_val.respond_to?(:empty?) && old_val.empty?)
              hsh[:new_value] = new_val unless new_val.nil? || (old_val.respond_to?(:empty?) && new_val.empty?)
              hsh[:element] = element
              hsh[:details] = details_hash unless details_hash.empty?
              hsh
            end
          end

          def diff_change_result(type, old_value, new_value, element = nil, details = {})
            element = if element.nil?
                        get_element_from = old_value || new_value
                        get_element_from.respond_to?(:label) ? get_element_from.label.to_sym : :plain_object
                      else
                        element
                      end
            DiffChangeResult.new(type, old_value, new_value, element, details)
          end

          def check_diffable!(other)
            raise DiffableObjectError.new(self, other) unless other.class.included_modules.include?(DiffableObject)
            raise NotSameClassError.new(self, other) unless other.instance_of?(self.class)
          end

          # Diff two parser objects
          # @param other [Object] The object to compare to. Must be an instance
          #   of the same class as the object being diffed.
          # @return [DiffChangeResult] The result of the diff
          def diff(other)
            return if other.nil?

            check_diffable!(other)
            case self
            when AbideDevUtils::XCCDF::Parser::Objects::AttributeValue,
                 AbideDevUtils::XCCDF::Parser::Objects::ControlURI,
                 AbideDevUtils::XCCDF::Parser::Objects::Description,
                 AbideDevUtils::XCCDF::Parser::Objects::Fixtext,
                 AbideDevUtils::XCCDF::Parser::Objects::LongText,
                 AbideDevUtils::XCCDF::Parser::Objects::Platform,
                 AbideDevUtils::XCCDF::Parser::Objects::Rationale,
                 AbideDevUtils::XCCDF::Parser::Objects::ShortText,
                 AbideDevUtils::XCCDF::Parser::Objects::System,
                 AbideDevUtils::XCCDF::Parser::Objects::Title,
                 AbideDevUtils::XCCDF::Parser::Objects::Version
              diff_str_obj(self, other)
            when AbideDevUtils::XCCDF::Parser::Objects::Rule
              diff_rule(self, other)
            when AbideDevUtils::XCCDF::Parser::Objects::Check
              diff_check(self, other)
            when AbideDevUtils::XCCDF::Parser::Objects::ComplexCheck
              diff_complex_check(self, other)
            when AbideDevUtils::XCCDF::Parser::Objects::XccdfSelect
              diff_xccdf_select(self, other)
            when AbideDevUtils::XCCDF::Parser::Objects::Value
              diff_value(self, other)
            when AbideDevUtils::XCCDF::Parser::Objects::Group
              diff_group(self, other)
            when AbideDevUtils::XCCDF::Parser::Objects::Profile
              diff_profile(self, other)
            when AbideDevUtils::XCCDF::Parser::Objects::Benchmark
              diff_benchmark(self, other)
            else
              diff_ambiguous(self, other, called_from_diff: true)
            end
          end

          def diff_ambiguous(self_obj, other_obj, called_from_diff: false)
            return if other_obj.nil?

            if self_obj.is_a?(Array) && other_obj.is_a?(Array)
              diff_array_obj(self_obj, other_obj)
            elsif self_obj.respond_to?(:diff) && other_obj.respond_to?(:diff) && !called_from_diff
              self_obj.diff(other_obj)
            elsif self_obj.respond_to?(:to_s) && other_obj.respond_to?(:to_s)
              diff_str_obj(self_obj, other_obj)
            else
              diff_plain_obj(self_obj, other_obj)
            end
          end

          def diff_plain_obj(self_obj, other_obj)
            result = self_obj == other_obj ? :equal : :not_equal
            d_hash = {
              self_ivars: self_obj.iv_to_h,
              other_ivars: other_obj.iv_to_h,
            }
            diff_change_result(result, self_obj, other_obj, d_hash)
          end

          def diff_str_obj(self_obj, other_obj)
            result = self_obj.to_s == other_obj.to_s ? :equal : :not_equal
            diff_change_result(result, self_obj, other_obj)
          end

          def diff_array_obj(self_ary, other_ary)
            sorted_self = self_ary.sort
            sorted_other = other_ary.sort
            added_ary = (sorted_other - sorted_self).map { |i| diff_change_result(:added, nil, i) }
            removed_ary = (sorted_self - sorted_other).map { |i| diff_change_result(:removed, i, nil) }
            changed_ary = correlate_added_removed(added_ary, removed_ary)
            diffable_self = sorted_self - (changed_ary.map(&:old_value) + changed_ary.map(&:new_value)).compact
            diffable_other = sorted_other - (changed_ary.map(&:old_value) + changed_ary.map(&:new_value)).compact
            diff_ary = diffable_self.zip(diffable_other).filter_map do |(self_obj, other_obj)|
              change = diff_ambiguous(self_obj, other_obj)
              if change.type == :equal
                nil
              else
                change
              end
            end
            diff_ary + changed_ary
          end

          def correlate_added_removed(added_ary, removed_ary)
            return [] if added_ary.empty? && removed_ary.empty?

            actual_added = added_ary.dup
            actual_removed = removed_ary.dup
            correlated = added_ary.each_with_object([]) do |added, ary|
              similarity = nil
              removed = removed_ary.find do |r|
                similarity = added.new_value.find_similarity(r.old_value)
                similarity.any? { |s| s[3] }
              end
              next if removed.nil?

              details_hash = {}
              similarity.each do |similar|
                details_hash[similar[0]] = similar[1..2] unless similar[3]
              end
              ary << diff_change_result(:not_equal, removed.old_value, added.new_value, nil, details_hash)
              actual_added.delete(added)
              actual_removed.delete(removed)
            end
            (correlated + actual_added + actual_removed).uniq
          end

          def diff_rule(self_rule, other_rule, diff_properties: %i[number title])
            d_hash = diff_properties.each_with_object({}) do |prop, hsh|
              hsh[prop] = diff_ambiguous(self_rule.send(prop), other_rule.send(prop))
            end
            result = result_from_details_hash(d_hash)
            d_hash = process_details_hash!(d_hash)
            diff_change_result(result, self_rule, other_rule, :rule, d_hash)
          end

          def diff_check(self_check, other_check)
            d_hash = {
              system: self_check.system.diff(other_check.system),
              check_export: diff_ambiguous(self_check.check_export, other_check.check_export),
              check_content_ref: diff_ambiguous(self_check.check_content_ref, other_check.check_content_ref),
            }
            result = result_from_details_hash(d_hash)
            d_hash = process_details_hash!(d_hash)
            diff_change_result(result, self_check, other_check, :check, d_hash)
          end

          def diff_complex_check(self_complex_check, other_complex_check)
            d_hash = {
              operator: self_complex_check.operator.diff(other_complex_check.operator),
              check: diff_array_obj(self_complex_check.check, other_complex_check.check),
            }
            result = result_from_details_hash(d_hash)
            d_hash = process_details_hash!(d_hash)
            diff_change_result(result, self_complex_check, other_complex_check, :complex_check, d_hash)
          end

          def diff_xccdf_select(self_select, other_select)
            d_hash = {
              idref: diff_str_obj(self_select.to_s, other_select.to_s),
              selected: diff_str_obj(self_select.selected, other_select.selected),
            }
            result = result_from_details_hash(d_hash)
            d_hash = process_details_hash!(d_hash)
            diff_change_result(result, self_select, other_select, :xccdf_select, d_hash)
          end

          def diff_value(self_value, other_value)
            d_hash = {
              title: self_value.title.diff(other_value.title),
              description: self_value.description.diff(other_value.description),
              text: diff_str_obj(self_value.text.to_s, other_value.text.to_s),
              operator: self_value.operator.diff(other_value.operator),
              type: self_value.type.diff(other_value.type),
            }
            result = result_from_details_hash(d_hash)
            d_hash = process_details_hash!(d_hash)
            diff_change_result(result, self_value, other_value, :value, d_hash)
          end

          def diff_group(self_group, other_group)
            d_hash = {
              title: self_group.title.diff(other_group.title),
              description: self_group.description.diff(other_group.description),
            }
            if self_group.respond_to?(:group) && other_group.respond_to?(:group)
              d_hash[:group] ||= []
              g_diff = diff_ambiguous(self_group.group, other_group.group)
              if g_diff.is_a?(Array)
                d_hash[:group] += g_diff
              else
                d_hash[:group] << g_diff
              end
            end
            if self_group.respond_to?(:rule) && other_group.respond_to?(:rule)
              d_hash[:rule] ||= []
              r_diff = diff_ambiguous(self_group.rule, other_group.rule)
              if r_diff.is_a?(Array)
                d_hash[:rule] += r_diff
              else
                d_hash[:rule] << r_diff
              end
            end
            result = result_from_details_hash(d_hash)
            d_hash = process_details_hash!(d_hash)
            diff_change_result(result, self_group, other_group, :group, d_hash)
          end

          def diff_profile(self_profile, other_profile)
            d_hash = {
              title: self_profile.title.diff(other_profile.title),
              description: self_profile.description.diff(other_profile.description),
              level: diff_str_obj(self_profile.level, other_profile.level),
              xccdf_select: diff_ambiguous(self_profile.xccdf_select, other_profile.xccdf_select),
            }
            result = result_from_details_hash(d_hash)
            d_hash = process_details_hash!(d_hash)
            diff_change_result(result, self_profile, other_profile, :profile, d_hash)
          end

          def diff_benchmark(self_benchmark, other_benchmark)
            d_hash = {}
            d_hash[:title] = self_benchmark.title.diff(other_benchmark.title)
            d_hash[:description] = self_benchmark.description.diff(other_benchmark.description)
            d_hash[:platform] = self_benchmark.platform.diff(other_benchmark.platform)
            d_hash[:profile] = diff_ambiguous(self_benchmark.profile, other_benchmark.profile)
            d_hash[:group] = diff_ambiguous(self_benchmark.group, other_benchmark.group)
            d_hash[:value] = diff_ambiguous(self_benchmark.value, other_benchmark.value)
            result = result_from_details_hash(d_hash)
            d_hash = process_details_hash!(d_hash)
            diff_change_result(result, self_benchmark, other_benchmark, :benchmark, d_hash)
          end

          def process_details_hash!(d_hash, _element = :plain_object)
            d_hash.reject! do |_, v|
              v.nil? || (v.empty? if v.respond_to?(:empty?)) || (v.type == :equal if v.respond_to?(:type))
            end
            d_hash
          end

          def result_from_details_hash(d_hash)
            changed_types = %i[not_equal added removed]
            results = d_hash.values.find do |v|
              if v.is_a?(Array)
                v.map(&:type).any? { |i| changed_types.include?(i) }
              elsif v.respond_to?(:type)
                changed_types.include?(v&.type)
              end
            end
            results.nil? ? :equal : :not_equal
          end
        end
      end
    end
  end
end
