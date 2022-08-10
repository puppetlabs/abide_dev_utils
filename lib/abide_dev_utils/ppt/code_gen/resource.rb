# frozen_string_literal: true

module AbideDevUtils
  module Ppt
    module CodeGen
      class Resource
        attr_reader :type, :title

        def initialize(type, title, **attributes)
          validate_type_and_title(type, title)
          @type = type
          @title = title
          @attributes = attributes
        end

        def reference
          "#{title.split('::').map(&:capitalize).join('::')}['#{title}']"
        end

        def to_s
          return "#{type} { '#{title}': }" if @attributes.empty?

          str_array = ["#{type} { '#{title}':"]
          @attributes.each do |key, val|
            str_array << "  #{pad_attribute(key)} => #{val},"
          end
          str_array << '}'
          str_array.join("\n")
        end

        private

        def validate_type_and_title(type, title)
          raise 'Type / title must be String' unless type.is_a?(String) && title.is_a?(String)
          raise 'Type / title must not be empty' if type.empty? || title.empty?
        end

        def longest_attribute_length
          return @longest_attribute_length if defined?(@longest_attribute_length)

          longest = ''
          @attributes.each_key do |k|
            longest = k if k.length > longest.length
          end
          @longest_attribute_length = longest.length
          @longest_attribute_length
        end

        def pad_attribute(attribute)
          return attribute if attribute.length == longest_attribute_length

          attr_array = [attribute]
          (longest_attribute_length - attribute.length).times { attr_array << ' ' }
          attr_array.join
        end
      end
    end
  end
end
