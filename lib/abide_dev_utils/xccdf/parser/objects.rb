# frozen_string_literal: true

require 'digest'
require_relative './objects/digest_object'
require_relative './objects/numbered_object'
require_relative './helpers'

module AbideDevUtils
  module XCCDF
    module Parser
      # Holds individual XCCDF objects
      module Objects
        # Base class for XCCDF element objects
        class ElementBase
          include AbideDevUtils::XCCDF::Parser::Objects::DigestObject
          include AbideDevUtils::XCCDF::Parser::Helpers::ElementChildren
          include AbideDevUtils::XCCDF::Parser::Helpers::XPath
          extend AbideDevUtils::XCCDF::Parser::Helpers::XPath
          attr_reader :children, :child_labels, :link_labels

          def initialize(*_args, **_kwargs)
            @children = []
            @links = []
            @link_labels = []
            @child_labels = []
            @label_method_values = {}
            exclude_from_digest(%i[@digest @children @child_labels @label @exclude_from_digest @label_method_values])
          end

          # For subclasses that are associated with a specific
          # XCCDF element, this method returns the element's
          # xpath name. Must be overridden by subclasses that
          # implement this method.
          def self.xpath
            nil
          end

          # For subclasses that are associated with a specific
          # XCCDF element that has valid namespace prefix,
          # this method returns that namespaces. May be
          # overridden by subclasses if they have a different
          # valid namespace prefix.
          def self.xmlns
            'xccdf'
          end

          # Takes the last segment of the class name, splits on captial letters,
          # and returns a downcased string joined by dashes. This gives us the
          # XCCDF element type. Example: 'AbideDevUtils::XCCDF::Parser::Objects::ComplexCheck'
          # returns 'complex-check'.
          def xccdf_type
            self.class.name.split('::').last.split(/(?=[A-Z])/).reject { |x| x == 'Xccdf' }.join('-').downcase
          end

          def all_values
            @child_labels.map { |label| send(label.to_sym) }
            @label_method_values
          end

          # Allows access to child objects by label
          def method_missing(method_name, *args, &block)
            m_name_string = method_name.to_s.downcase
            return @label_method_values[m_name_string] if @label_method_values.key?(m_name_string)

            label_str = m_name_string.start_with?('linked_') ? m_name_string.split('_')[1..].join('_') : m_name_string
            if m_name_string.start_with?('linked_') && @link_labels.include?(label_str)
              found = @links.select { |link| link.label == label_str }
              @label_method_values["linked_#{label_str}"] = if found.length == 1
                                                              found.first
                                                            else
                                                              found
                                                            end
              @label_method_values["linked_#{label_str}"]
            elsif @child_labels.include?(label_str)
              found = @children.select { |child| child.label == label_str }
              @label_method_values[label_str] = if found.length == 1
                                                  found.first
                                                else
                                                  found
                                                end
              @label_method_values[label_str]
            elsif search_children.respond_to?(method_name)
              search_children.send(method_name, *args, &block)
            else
              super
            end
          end

          def respond_to_missing?(method_name, include_private = false)
            m_name_string = method_name.to_s.downcase
            label_str = m_name_string.start_with?('linked_') ? m_name_string.split('_')[1..].join('_') : m_name_string
            (m_name_string.start_with?('linked_') && @link_labels.include?(label_str)) ||
              @child_labels.include?(label_str) ||
              super
          end

          def label
            return @label if defined?(@label)

            @label = case self.class.name
                     when 'AbideDevUtils::XCCDF::Parser::Objects::AttributeValue'
                       @attribute.to_s
                     when /AbideDevUtils::XCCDF::Parser::Objects::(ShortText|LongText)/
                       'text'
                     else
                       self.class.name.split('::').last.split(/(?=[A-Z])/).join('_').downcase
                     end
            @label
          end

          def add_link(object)
            @links << object
            @link_labels << object.label unless @link_labels.include?(object.label)
          end

          def add_links(objects)
            objects.each { |object| add_object_as_child(object) }
          end

          private

          def with_safe_methods(default: nil)
            yield
          rescue NoMethodError
            default
          end

          def add_child(klass, element, *args, **kwargs)
            return if element.nil?

            real_element = klass.xpath.nil? ? element : find_element.at_xpath(element, klass.xpath)
            return if real_element.nil?

            obj = new_object(klass, real_element, *args, **kwargs)
            @children << obj
            @child_labels << obj.label unless @child_labels.include?(obj.label)
          rescue StandardError => e
            raise(
              e,
              "Failed to add child #{klass.to_s.split('::').last} to #{self.class.to_s.split('::').last}: #{e.message}",
              e.backtrace,
            )
          end

          def add_children(klass, element, *args, **kwargs)
            return if element.nil?

            real_elements = klass.xpath.nil? ? element : find_element.xpath(element, klass.xpath)
            return if real_elements.nil?

            real_elements.each do |e|
              obj = new_object(klass, e, *args, **kwargs)
              @children << obj
              @child_labels << obj.label unless @child_labels.include?(obj.label)
            end
          rescue StandardError => e
            raise(
              e,
              "Failed to add children #{klass.to_s.split('::').last} to #{self.class.to_s.split('::').last}: #{e.message}",
              e.backtrace,
            )
          end

          def new_object(klass, element, *args, **kwargs)
            klass.new(element, *args, **kwargs)
          end
        end

        # Holds text content that does not use multiple lines
        class ShortText < ElementBase
          attr_reader :text

          def initialize(element)
            super
            text = element.respond_to?(:text) ? element.text : element
            @text = text.to_s
          end

          def to_s
            @text
          end
        end

        # Holds text content that consists of multiple lines
        class LongText < ElementBase
          attr_reader :text

          def initialize(element)
            super
            text = element.respond_to?(:text) ? element.text : element
            @text = text.to_s
            @string_text = text.to_s.tr("\n", ' ').gsub(/\s+/, ' ')
          end

          def to_s
            @string_text
          end
        end

        # Represents a value of an element attribute
        class AttributeValue < ElementBase
          attr_reader :attribute, :value

          def initialize(element, attribute)
            super
            @attribute = attribute
            @value = element[attribute]
          end

          def to_s
            "#{@attribute}=#{@value}"
          end
        end

        # Class for an XCCDF element title
        class Title < ElementBase
          def initialize(element)
            super
            add_child(ShortText, element)
          end

          def self.xpath
            'title'
          end

          def to_s
            search_children.find_child_by_class(ShortText).to_s
          end
        end

        # Class for an XCCDF element description
        class Description < ElementBase
          def initialize(element)
            super
            add_child(LongText, element)
          end

          def self.xpath
            'description'
          end

          def to_s
            search_children.find_child_by_class(LongText).to_s
          end
        end

        # Base class for elements that have the ID attribute
        class ElementWithId < ElementBase
          attr_reader :id

          def initialize(element)
            super
            add_child(AttributeValue, element, 'id')
            @id = search_children.find_child_by_attribute('id').value.to_s
          end

          def to_s
            @id
          end
        end

        # Base class for elements that have the idref attribute
        class ElementWithIdref < ElementBase
          attr_reader :idref

          def initialize(element)
            super
            add_child(AttributeValue, element, 'idref')
            @idref = search_children.find_child_by_attribute('idref').value.to_s
          end

          def to_s
            @idref
          end
        end

        # Class for an XCCDF select element
        class XccdfSelect < ElementWithIdref
          def initialize(element)
            super
            add_child(AttributeValue, element, 'selected')
          end

          def self.xpath
            'select'
          end
        end

        # Class for XCCDF profile
        class Profile < ElementWithId
          def initialize(element)
            super
            add_child(Title, element)
            add_child(Description, element)
            add_children(XccdfSelect, element)
          end

          def level
            return @level if defined?(@level)

            level_match = title.to_s.match(/([Ll]evel [0-9]+)/)
            @level = level_match.nil? ? level_match : level_match[1]
            @level
          end

          def self.xpath
            'Profile'
          end
        end

        # Class for XCCDF group
        class Group < ElementWithId
          include AbideDevUtils::XCCDF::Parser::Objects::NumberedObject
          attr_reader :number

          def initialize(element)
            super
            @number = to_s[/group_([0-9]+\.)+[0-9]+|group_([0-9]+)/]&.gsub(/group_/, '')
            add_child(Title, element)
            add_child(Description, element)
            add_children(Group, element)
            add_children(Rule, element)
          end

          def self.xpath
            'Group'
          end
        end

        # Class for XCCDF check-export
        class CheckExport < ElementBase
          def initialize(element)
            super
            add_child(AttributeValue, element, 'export-name')
            add_child(AttributeValue, element, 'value-id')
          end

          def self.xpath
            'check-export'
          end

          def to_s
            [search_children.find_child_by_attribute('export-name').to_s, search_children.find_child_by_attribute('value-id').to_s].join('|')
          end
        end

        # Class for XCCDF check-content-ref
        class CheckContentRef < ElementBase
          def initialize(element)
            super
            add_child(AttributeValue, element, 'href')
            add_child(AttributeValue, element, 'name')
          end

          def self.xpath
            'check-content-ref'
          end

          def to_s
            [search_children.find_child_by_attribute('href').to_s, search_children.find_child_by_attribute('name').to_s].join('|')
          end
        end

        # Class for XCCDF check
        class Check < ElementBase
          def initialize(element)
            super
            add_child(AttributeValue, element, 'system')
            add_children(CheckExport, element)
            add_children(CheckContentRef, element)
          end

          def self.xpath
            'check'
          end
        end

        # Class for XCCDF Ident ControlURI element
        class ControlURI < ElementBase
          def initialize(element)
            super
            @namespace = element.attributes['controlURI'].namespace.prefix
            @value = element.attributes['controlURI'].value
          end

          def to_s
            [label, @namespace, @value].join(':')
          end
        end

        # Class for XCCDF Ident System element
        class System < ElementBase
          def initialize(element)
            super
            @system = element.attributes['system'].value
            @text = element.text
          end

          def to_s
            [label, @system, @text].join(':')
          end
        end

        # Class for XCCDF rule ident
        class Ident < ElementBase
          def initialize(element)
            super
            with_safe_methods { add_child(ControlURI, element) }
            with_safe_methods { add_child(System, element) }
          end

          def self.xpath
            'ident'
          end

          def to_s
            @children.map(&:to_s).join('|')
          end
        end

        # Class for XCCDF rule complex check
        class ComplexCheck < ElementBase
          attr_reader :operator, :check

          def initialize(element, parent: nil)
            super
            add_child(AttributeValue, element, 'operator')
            add_children(Check, element)
          end

          def self.xpath
            'complex-check'
          end
        end

        # Class for XCCDF rule metadata cis_controls framework safeguard
        class MetadataCisControlsFrameworkSafeguard < ElementBase
          def initialize(element)
            super
            add_child(ShortText, element['title'])
            add_child(ShortText, element['urn'])
            new_implementation_groups(element)
            add_child(ShortText, find_element.at_xpath(element, 'asset_type').text)
            add_child(ShortText, find_element.at_xpath(element, 'security_function').text)
          end

          def self.xpath
            'safeguard'
          end

          def self.xmlns
            'controls'
          end

          private

          def new_implementation_groups(element)
            igroup = find_element.at_xpath(element, 'implementation_groups')
            return if igroup.nil? || igroup.empty?

            add_child(ShortText, igroup['ig1']) if igroup['ig1']
            add_child(ShortText, igroup['ig2']) if igroup['ig2']
            add_child(ShortText, igroup['ig3']) if igroup['ig3']
          end
        end

        # Class for XCCDF rule metadata cis_controls framework
        class MetadataCisControlsFramework < ElementBase
          def initialize(element)
            super
            add_child(AttributeValue, element, 'urn')
            add_children(MetadataCisControlsFrameworkSafeguard, element)
          end

          def self.xpath
            'framework'
          end

          def self.xmlns
            'controls'
          end
        end

        # Class for XCCDF metadata cis_controls element
        class MetadataCisControls < ElementBase
          def initialize(element, parent: nil)
            super
            add_child(AttributeValue, element, 'controls')
            add_children(MetadataCisControlsFramework, element)
          end

          def self.xpath
            'cis_controls'
          end

          def self.xmlns
            'controls'
          end
        end

        # class MetadataNotes < ElementBase
        #   def initialize()

        # Class for XCCDF rule metadata element
        class Metadata < ElementBase
          def initialize(element, parent: nil)
            super
            add_children(MetadataCisControls, element)
          end

          def self.xpath
            'metadata'
          end
        end

        # Class for XCCDF Rule child element Rationale
        class Rationale < ElementBase
          def initialize(element)
            super
            add_child(LongText, element)
          end

          def digest
            @digest ||= find_child_by_class(LongText).digest
          end

          def self.xpath
            'rationale'
          end

          def to_s
            find_child_by_class(LongText).to_s
          end
        end

        # Class for XCCDF Rule child element Fixtext
        class Fixtext < ElementBase
          def initialize(element)
            super
            add_child(LongText, element)
          end

          def digest
            @digest ||= search_children.find_child_by_class(LongText).digest
          end

          def self.xpath
            'fixtext'
          end

          def to_s
            search_children.find_child_by_class(LongText).to_s
          end
        end

        # Class for XCCDF rule
        class Rule < ElementWithId
          include AbideDevUtils::XCCDF::Parser::Objects::NumberedObject
          attr_reader :number

          def initialize(element)
            super
            @number = to_s[/([0-9]+\.)+[0-9]+/]
            add_child(AttributeValue, element, 'role')
            add_child(AttributeValue, element, 'selected')
            add_child(AttributeValue, element, 'weight')
            add_child(Title, element)
            add_child(Description, element)
            add_child(Rationale, element)
            add_children(Ident, element)
            add_child(Fixtext, element)
            add_children(Check, element)
            add_child(ComplexCheck, element)
            add_child(Metadata, element)
          end

          def self.xpath
            'Rule'
          end
        end

        # Class for XCCDF Value
        class Value < ElementWithId
          def initialize(element)
            super
            add_child(AttributeValue, element, 'operator')
            add_child(AttributeValue, element, 'type')
            add_child(Title, element)
            add_child(Description, element)
            add_child(ShortText, find_element.at_xpath(element, 'value'))
          end

          def self.xpath
            'Value'
          end

          def to_s
            search_children.find_child_by_class(Title).to_s
          end
        end

        # Class for XCCDF benchmark status
        class Status < ElementBase
          def initialize(element)
            super
            add_child(ShortText, element)
            add_child(AttributeValue, element, 'date')
          end

          def self.xpath
            'status'
          end

          def to_s
            [
              "Status:#{search_children.find_child_by_class(ShortText)}",
              "Date:#{search_children.find_child_by_class(AttributeValue)}",
            ].join('|')
          end
        end

        # Class for XCCDF benchmark version
        class Version < ElementBase
          def initialize(element)
            super
            add_child(ShortText, element)
          end

          def self.xpath
            'version'
          end

          def to_s
            search_children.find_child_by_class(ShortText).to_s
          end
        end

        # Class for XCCDF benchmark platform
        class Platform < ElementBase
          def initialize(element)
            super
            add_child(AttributeValue, element, 'idref')
          end

          def self.xpath
            'platform'
          end

          def to_s
            search_children.find_child_by_class(AttributeValue).to_s
          end
        end

        # Class for XCCDF benchmark
        class Benchmark < ElementBase
          include AbideDevUtils::XCCDF::Parser::Objects::NumberedObject

          def initialize(element)
            super
            elem = find_element.at_xpath(element, 'Benchmark')
            raise 'No Benchmark element found' if elem.nil?

            add_child(Status, elem)
            add_child(Title, elem)
            add_child(Description, elem)
            add_child(Platform, elem)
            add_child(Version, elem)
            add_children(Profile, elem)
            add_children(Group, elem)
            add_children(Value, elem)
          end

          def self.xpath
            'Benchmark'
          end

          def to_s
            [search_children.find_child_by_class(Title).to_s, search_children.find_child_by_class(Version).to_s].join(' ')
          end
        end
      end
    end
  end
end
