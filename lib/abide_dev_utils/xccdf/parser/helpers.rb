# frozen_string_literal: true

module AbideDevUtils
  module XCCDF
    module Parser
      module Helpers
        # Provides helper methods for working with XCCDF element children
        module ElementChildren
          def search_children
            @search_children ||= SearchChildren.new(children)
          end

          # Implements methods that allow for searching an XCCDF Element's children
          class SearchChildren
            attr_reader :children

            def initialize(children)
              @children = children
            end

            def recursive_select_children(children_to_search = children, &block)
              search_hits = []
              children_to_search.each do |child|
                found = yield child
                if found
                  search_hits << child
                elsif child.respond_to?(:children)
                  search_hits << recursive_select_children(child.children, &block)
                end
              end
              search_hits.flatten.compact.uniq
            end

            def recursive_find_child(children_to_search = children, &block)
              rescursive_select_children(children_to_search, &block).first
            end

            def find_children_that_respond_to(method, recurse: false)
              return recursive_select_children { |child| child.respond_to?(method) } if recurse

              children.select { |c| c.respond_to?(method.to_sym) }
            end

            def find_children_by_class(klass, recurse: false)
              return recursive_select_children { |child| child.instance_of?(klass) } if recurse

              children.select { |child| child.instance_of?(klass) }
            end

            def find_child_by_class(klass, recurse: false)
              return recursive_find_child { |child| child.is_a?(klass) } if recurse

              find_children_by_class(klass).first
            end

            def find_children_by_xpath(xpath, recurse: false)
              return recursive_select_children { |child| child.xpath == xpath } if recurse

              children.select { |child| child.xpath == xpath }
            end

            def find_child_by_xpath(xpath, recurse: false)
              return recursive_find_child { |child| child.xpath == xpath } if recurse

              find_children_by_xpath(xpath).first
            end

            def find_children_by_attribute(attribute, recurse: false)
              pr = proc do |child|
                next unless child.instance_of?(AbideDevUtils::XCCDF::Parser::Objects::AttributeValue)

                child.attribute == attribute
              end
              return recursive_select_children(&pr) if recurse

              children.select(&pr)
            end

            def find_child_by_attribute(attribute, recurse: false)
              find_children_by_attribute(attribute, recurse: recurse).first
            end

            def find_children_by_attribute_value(attribute, value, recurse: false)
              pr = proc do |child|
                next unless child.instance_of?(AbideDevUtils::XCCDF::Parser::Objects::AttributeValue)

                child.attribute == attribute && child.value == value
              end
              return recursive_select_children(&pr) if recurse

              children.select(&pr)
            end

            def find_child_by_attribute_value(attribute, value, recurse: false)
              find_children_by_attribute_value(attribute, value, recurse: recurse).first
            end
          end
        end

        # Provides helper methods for working with XML xpaths
        module XPath
          def find_element
            FindElement
          end

          # Implements class methods to help with finding elements via XPath
          class FindElement
            def self.xpath(element, path)
              elem = namespace_safe_xpath(element, path)
              return named_xpath(element, path) if elem.nil?

              elem
            end

            def self.at_xpath(element, path)
              elem = namespace_safe_at_xpath(element, path)
              return named_at_xpath(element, path) if elem.nil?

              elem
            end

            def self.namespace_safe_xpath(element, path)
              element.xpath(path)
            rescue Nokogiri::XML::XPath::SyntaxError
              named_xpath(element, path)
            end

            def self.namespace_safe_at_xpath(element, path)
              element.at_xpath(path)
            rescue Nokogiri::XML::XPath::SyntaxError
              named_at_xpath(element, path)
            end

            def self.named_xpath(element, path)
              element.xpath("*[name()='#{path}']")
            end

            def self.named_at_xpath(element, path)
              element.at_xpath("*[name()='#{path}']")
            end
          end
        end
      end
    end
  end
end
