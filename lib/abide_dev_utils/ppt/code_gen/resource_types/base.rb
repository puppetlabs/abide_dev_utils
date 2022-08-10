# frozen_string_literal: true

require 'securerandom'

module AbideDevUtils
  module Ppt
    module CodeGen
      # Base class for all code gen objects
      class Base
        attr_accessor :title, :id

        def initialize
          @id = SecureRandom.hex(10)
          @supports_value = false
          @supports_children = false
        end

        def to_s
          "#{type} : value: #{@value}; children: #{@children}"
        end

        def reference
          raise NotImplementedError, "#{type} does not support having a reference"
        end

        def type
          self.class.to_s
        end

        def value
          raise NotImplementedError, "#{type} does not support having a value" unless @supports_value

          @value
        end

        def get_my(t, named: nil)
          if named.nil?
            children.each_with_object([]) do |(k, v), arr|
              arr << v if k.start_with?("#{t.to_s.capitalize}_")
            end
          else
            children["#{t.to_s.capitalize}_#{named}"]
          end
        end

        # Creates a new object of the given type and adds it to the current objects children
        # if the current object supports children.
        # Returns `self`. If a block is given, the new
        # object will be yielded before adding to children.
        def with_a(t, named: nil)
          obj = Object.const_get("AbideDevUtils::Ppt::CodeGen::#{t.to_s.capitalize}").new
          obj.title = named unless named.nil? || named.empty?

          yield obj if block_given?

          children["#{t.to_s.capitalize}_#{obj.id}"] = obj
          self
        end
        alias and_a with_a

        def has_a(t, named: nil)
          obj = Object.const_get("AbideDevUtils::Ppt::CodeGen::#{t.to_s.capitalize}").new
          obj.title = named unless named.nil? || named.empty?
          children["#{t.to_s.capitalize}_#{obj.id}"] = obj
          obj
        end
        alias and_has_a has_a
        alias that_has_a has_a

        # Sets the explicit value of the current object if the current object has an explicit value.
        def that_equals(val)
          self.value = val
          self
        end
        alias and_assign_a_value_of that_equals
        alias has_a_value_of that_equals
        alias that_has_a_value_of that_equals

        private

        def children
          raise NotImplementedError, "#{type} does not support children" unless @supports_children

          @children ||= {}
        end

        def value=(val)
          @value = val if @supports_value
        end
      end
    end
  end
end
