# frozen_string_literal: true

module AbideDevUtils
  # Module provides comparison methods for "dot numbers", numbers that
  # take the form of "1.1.1" as found in CIS benchmarks. Classes that
  # include this module must implement a method "number" that returns
  # their dot number representation.
  module DotNumberComparable
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
  end
end
