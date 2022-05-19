# frozen_string_literal: true

require 'digest'
require_relative './objects/digest_object'
require_relative './objects/numbered_object'

module AbideDevUtils
  module XCCDF
    module Parser
      # Holds individual XCCDF objects
      module Objects
        # Base class for XCCDF element objects
        class ElementBase
          include AbideDevUtils::XCCDF::Parser::Objects::DigestObject
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
          # xpath. Must be overridden by subclasses that
          # implement this method.
          def self.xpath
            nil
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

          def namespace_safe_xpath(element, path)
            element.xpath(path)
          rescue Nokogiri::XML::XPath::SyntaxError
            element.xpath("*[name()='#{path}']")
          end

          def namespace_safe_at_xpath(element, path)
            element.at_xpath(path)
          rescue Nokogiri::XML::XPath::SyntaxError
            element.at_xpath("*[name()='#{path}']")
          end

          def add_child(klass, element, *args, **kwargs)
            return if element.nil?

            real_element = klass.xpath.nil? ? element : namespace_safe_at_xpath(element, klass.xpath)
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

            real_elements = klass.xpath.nil? ? element : namespace_safe_xpath(element, klass.xpath)
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
            'xccdf:title'
          end

          def to_s
            find_child_by_class(ShortText).to_s
          end
        end

        # Class for an XCCDF element description
        class Description < ElementBase
          def initialize(element)
            super
            add_child(LongText, element)
          end

          def self.xpath
            'xccdf:description'
          end

          def to_s
            find_child_by_class(LongText).to_s
          end
        end

        # Base class for elements that have the ID attribute
        class ElementWithId < ElementBase
          attr_reader :id

          def initialize(element)
            super
            add_child(AttributeValue, element, 'id')
            @id = find_child_by_attribute('id').value.to_s
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
            @idref = find_child_by_attribute('idref').value.to_s
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
            'xccdf:select'
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
            'xccdf:Profile'
          end
        end

        # Class for XCCDF group
        class Group < ElementWithId
          include AbideDevUtils::XCCDF::Parser::Objects::NumberedObject
          attr_reader :number

          def initialize(element)
            super
            @number = to_s[/group_([0-9]+\.)+[0-9]+|group_([0-9]+)/].gsub(/group_/, '')
            add_child(Title, element)
            add_child(Description, element)
            add_children(Group, element)
            add_children(Rule, element)
          end

          def self.xpath
            'xccdf:Group'
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
            'xccdf:check-export'
          end

          def to_s
            [find_child_by_attribute('export-name').to_s, find_child_by_attribute('value-id').to_s].join('|')
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
            'xccdf:check-content-ref'
          end

          def to_s
            [find_child_by_attribute('href').to_s, find_child_by_attribute('name').to_s].join('|')
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
            'xccdf:check'
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
            'xccdf:ident'
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
            'xccdf:complex-check'
          end
        end

        # Class for XCCDF rule metadata cis_controls framework safeguard
        class MetadataCisControlsFrameworkSafeguard < ElementBase
          def initialize(element)
            super
            add_child(ShortText, element['title'])
            add_child(ShortText, element['urn'])
            new_implementation_groups(element)
            add_child(ShortText, namespace_safe_at_xpath(element, 'controls:asset_type').text)
            add_child(ShortText, namespace_safe_at_xpath(element, 'controls:security_function').text)
          end

          def self.xpath
            'controls:safeguard'
          end

          private

          def new_implementation_groups(element)
            igroup = namespace_safe_at_xpath(element, 'controls:implementation_groups')
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
            'controls:framework'
          end
        end

        # Class for XCCDF metadata cis_controls element
        class MetadataCisControls < ElementBase
          def initialize(element, parent: nil)
            super
            add_child(AttributeValue, element, 'xmlns:controls')
            add_children(MetadataCisControlsFramework, element)
          end

          def self.xpath
            'controls:cis_controls'
          end
        end

        # Class for XCCDF rule metadata element
        class Metadata < ElementBase
          def initialize(element, parent: nil)
            super
            add_children(MetadataCisControls, element)
          end

          def self.xpath
            'xccdf:metadata'
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
            'xccdf:rationale'
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
            @digest ||= find_child_by_class(LongText).digest
          end

          def self.xpath
            'xccdf:fixtext'
          end

          def to_s
            find_child_by_class(LongText).to_s
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
            'xccdf:Rule'
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
            add_child(ShortText, element.at_xpath('xccdf:value'))
          end

          def self.xpath
            'xccdf:Value'
          end

          def to_s
            find_child_by_class(Title).to_s
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
            'xccdf:status'
          end

          def to_s
            [
              "Status:#{find_child_by_class(ShortText)}",
              "Date:#{find_child_by_class(AttributeValue)}",
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
            'xccdf:version'
          end

          def to_s
            find_child_by_class(ShortText).to_s
          end
        end

        # Class for XCCDF benchmark platform
        class Platform < ElementBase
          def initialize(element)
            super
            add_child(AttributeValue, element, 'idref')
          end

          def self.xpath
            'xccdf:platform'
          end

          def to_s
            find_child_by_class(AttributeValue).to_s
          end
        end

        # Class for XCCDF benchmark
        class Benchmark < ElementBase
          include AbideDevUtils::XCCDF::Parser::Objects::NumberedObject

          def initialize(element)
            super
            element = element.at_xpath('xccdf:Benchmark')
            raise 'No Benchmark element found' if element.nil?

            add_child(Status, element)
            add_child(Title, element)
            add_child(Description, element)
            add_child(Platform, element)
            add_child(Version, element)
            add_children(Profile, element)
            add_children(Group, element)
            add_children(Value, element)
          end

          def self.xpath
            'xccdf:Benchmark'
          end

          def to_s
            [find_child_by_class(Title).to_s, find_child_by_class(Version).to_s].join(' ')
          end
        end
      end
    end
  end
end
