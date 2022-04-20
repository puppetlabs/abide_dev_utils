# frozen_string_literal: true

module AbideDevUtils
  module XCCDF
    module Parser
      module Objects
        # Methods for interacting with objects that have numbers (e.g. Group, Rule, etc.)
        # This module is included in the Benchmark class and Group / Rule classes
        module NumberedObject
          include ::Comparable

          def <=>(other)
            return 0 if number_eq(number, other.number)
            return 1 if number_gt(number, other.number)
            return -1 if number_lt(number, other.number)
          end

          def number_eq(this_num, other_num)
            this_num == other_num
          end

          def number_parent_of?(this_num, other_num)
            return false if number_eq(this_num, other_num)

            # We split the numbers into parts and compare the resulting arrays
            num1_parts = this_num.to_s.split('.')
            num2_parts = other_num.to_s.split('.')
            # For this_num to be a parent of other_num, the number of parts in
            # this_num must be less than the number of parts in other_num.
            # Additionally, each part of this_num must be equal to the parts of
            # other_num at the same index.
            # Example: this_num = '1.2.3' and other_num = '1.2.3.4'
            # In this case, num1_parts = ['1', '2', '3'] and num2_parts = ['1', '2', '3', '4']
            # So, this_num is a parent of other_num because at indexes 0, 1, and 2
            # of num1_parts and num2_parts, the parts are equal.
            num1_parts.length < num2_parts.length &&
              num2_parts[0..(num1_parts.length - 1)] == num1_parts
          end

          def number_child_of?(this_num, other_num)
            number_parent_of?(other_num, this_num)
          end

          def number_gt(this_num, other_num)
            return false if number_eq(this_num, other_num)
            return true if number_parent_of?(this_num, other_num)

            num1_parts = this_num.to_s.split('.')
            num2_parts = other_num.to_s.split('.')
            num1_parts.zip(num2_parts).each do |num1_part, num2_part|
              next if num1_part == num2_part # we skip past equal parts

              # If num1_part is nil that means that we've had equal numbers so far.
              # Therfore, this_num is greater than other num because of the
              # hierarchical nature of the numbers.
              # Example: this_num = '1.2' and other_num = '1.2.3'
              # In this case, num1_part is nil and num2_part is '3'
              # So, this_num is greater than other_num
              return true if num1_part.nil?
              # If num2_part is nil that means that we've had equal numbers so far.
              # Therfore, this_num is less than other num because of the
              # hierarchical nature of the numbers.
              # Example: this_num = '1.2.3' and other_num = '1.2'
              # In this case, num1_part is '3' and num2_part is nil
              # So, this_num is less than other_num
              return false if num2_part.nil?

              return num1_part.to_i > num2_part.to_i
            end
          end

          def number_lt(this_num, other_num)
            number_gt(other_num, this_num)
          end

          # This method will recursively walk the tree to find the first
          # child, grandchild, etc. that has a number method and returns the
          # matching number.
          # @param [String] number The number to find in the tree
          # @return [Group] The first child, grandchild, etc. that has a matching number
          # @return [Rule] The first child, grandchild, etc. that has a matching number
          # @return [nil] If no child, grandchild, etc. has a matching number
          def search_children_by_number(number)
            find_children_that_respond_to(:number).find do |child|
              if number_eq(child.number, number)
                child
              elsif number_parent_of?(child.number, number)
                # We recursively search the child for its child with the number
                # if our number is a parent of the child's number
                return child.search_children_by_number(number)
              end
            end
          end

          def find_child_by_number(number)
            find_children_that_respond_to(:number).find do |child|
              number_eq(child.number, number)
            end
          end
        end
      end
    end
  end
end
