# frozen_string_literal: true

module AbideDevUtils
  module XCCDF
    module Parser
      module Helpers
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
