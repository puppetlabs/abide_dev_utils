# frozen_string_literal: true

require_relative './objects/diffable_object'
require_relative './objects/numbered_object'
require_relative './helpers'

module AbideDevUtils
  module XCCDF
    module Parser
      # Holds individual XCCDF objects
      module Objects
        # Base class for XCCDF element objects
        class ElementBase
          include Comparable
          include AbideDevUtils::XCCDF::Parser::Objects::DiffableObject
          include AbideDevUtils::XCCDF::Parser::Helpers::XPath
          extend AbideDevUtils::XCCDF::Parser::Helpers::XPath

          UNICODE_SYMBOLS = {
            vertical: "\u2502",
            horizontal: "\u2500",
            tee: "\u251C",
            corner: "\u2514"
          }.freeze

          attr_reader :children, :child_labels, :links, :link_labels, :parent

          def initialize(*_args, parent_node: nil, **_kwargs)
            @parent = parent_node
            @children = []
            @links = []
            @link_labels = []
            @child_labels = []
            @label_method_values = {}
            @similarity_methods = []
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

          def inspect
            "<#{self.class}:#{object_id}:\"#{self}\">"
          end

          def <=>(other)
            return nil unless other.is_a?(self.class)

            label <=> other.label
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

          def find_similarity(other)
            return [] unless other.is_a?(self.class)

            @similarity_methods.each_with_object([]) do |method, ary|
              val = send(method)
              other_val = other.send(method)
              ary << [method, val, other_val, val.eql?(other_val)]
            end
          end

          def add_link(object)
            define_child_method(object.label, linked: true)
            @links << object
            @link_labels << object.label unless @link_labels.include?(object.label)
          end

          def add_links(objects)
            objects.each { |object| add_link(object) }
          end

          def root?
            parent.nil?
          end

          def root
            return self if root?

            parent.root
          end

          def leaf?
            children.empty?
          end

          def siblings
            return [] if root?

            parent.children.reject { |child| child == self }
          end

          def ancestors
            return [] if root?

            [parent] + parent.ancestors
          end

          def descendants
            return [] if leaf?

            children + children.map(&:descendants).flatten
          end

          def depth
            return 0 if root?

            1 + parent.depth
          end

          def print_tree
            puts tree_string_parts.join("\n")
          end

          protected

          def tree_string_parts(indent = 0, parts = [])
            parts << if indent.zero?
                       "#{UNICODE_SYMBOLS[:vertical]} #{inspect}".encode('utf-8')
                     elsif !children.empty?
                       "#{UNICODE_SYMBOLS[:tee]}#{UNICODE_SYMBOLS[:horizontal] * indent} #{inspect}".encode('utf-8')
                     else
                       "#{UNICODE_SYMBOLS[:corner]}#{UNICODE_SYMBOLS[:horizontal] * indent} #{inspect}".encode('utf-8')
                     end
            children.each { |c| c.tree_string_parts(indent + 2, parts) } unless children.empty?
            parts
          end

          private

          def similarity_methods(*methods)
            @similarity_methods = methods
          end

          def with_safe_methods(default: nil)
            yield
          rescue NoMethodError
            default
          end

          def define_child_method(child_label, linked: false)
            method_name = linked ? "linked_#{child_label}" : child_label
            self.class.define_method method_name do
              found = if method_name.start_with?('linked_')
                        @links.select { |l| l.label == child_label }
                      else
                        children.select { |c| c.label == child_label }
                      end
              if found.length == 1
                found.first
              else
                found
              end
            end
          end

          def add_child(klass, element, *args, **kwargs)
            return if element.nil?

            real_element = klass.xpath.nil? ? element : find_element.at_xpath(element, klass.xpath)
            return if real_element.nil?

            obj = new_object(klass, real_element, *args, parent_node: self, **kwargs)
            define_child_method(obj.label)
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
              obj = new_object(klass, e, *args, parent_node: self, **kwargs)
              define_child_method(obj.label)
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

          def initialize(element, parent_node: nil)
            super
            text = element.respond_to?(:text) ? element.text : element
            @text = text.to_s
          end

          def eql?(other)
            text == other.text
          end

          def hash
            text.hash
          end

          def to_s
            @text
          end
        end

        # Holds text content that consists of multiple lines
        class LongText < ElementBase
          attr_reader :text

          def initialize(element, parent_node: nil)
            super
            text = element.respond_to?(:text) ? element.text : element
            @text = text.to_s
            @string_text = text.to_s.tr("\n", ' ').gsub(/\s+/, ' ')
            similarity_methods :to_s
          end

          def eql?(other)
            @string_text == other.to_s
          end

          def hash
            @string_text.hash
          end

          def to_s
            @string_text
          end
        end

        # Represents a value of an element attribute
        class AttributeValue < ElementBase
          attr_reader :attribute, :value

          def initialize(element, attribute, parent_node: nil)
            super
            @attribute = attribute
            @value = element[attribute]
            similarity_methods :attribute, :value
          end

          def eql?(other)
            @attribute == other.attribute && @value == other.value
          end

          def hash
            to_s.hash
          end

          def to_s
            "#{@attribute}=#{@value}"
          end
        end

        # Class for an XCCDF element title
        class Title < ElementBase
          def initialize(element, parent_node: nil)
            super
            add_child(ShortText, element)
          end

          def self.xpath
            'title'
          end

          def eql?(other)
            to_s == other.to_s
          end

          def hash
            to_s.hash
          end

          def to_s
            text.to_s
          end
        end

        # Class for an XCCDF element description
        class Description < ElementBase
          def initialize(element, parent_node: nil)
            super
            add_child(LongText, element)
          end

          def self.xpath
            'description'
          end

          def eql?(other)
            to_s == other.to_s
          end

          def hash
            to_s.hash
          end

          def to_s
            text.to_s
          end
        end

        # Base class for elements that have the ID attribute
        class ElementWithId < ElementBase
          attr_reader :id

          def initialize(element, parent_node: nil)
            super
            add_child(AttributeValue, element, 'id')
            @id = descendants.find { |d| d.label == 'id' }.value
          end

          def <=>(other)
            return nil unless other.instance_of?(self.class)

            @id <=> other.id.value
          end

          def eql?(other)
            @id == other.id.value
          end

          def hash
            @id.hash
          end

          def to_s
            @id
          end
        end

        # Base class for elements that have the idref attribute
        class ElementWithIdref < ElementBase
          attr_reader :idref

          def initialize(element, parent_node: nil)
            super
            add_child(AttributeValue, element, 'idref')
            @idref = descendants.find { |d| d.label == 'idref' }.value
          end

          def <=>(other)
            return nil unless other.instance_of?(self.class)

            @idref <=> other.idref.value
          end

          def eql?(other)
            @idref == other.idref.value
          end

          def hash
            @idref.hash
          end

          def to_s
            @idref
          end
        end

        # Class for an XCCDF select element
        class XccdfSelect < ElementWithIdref
          attr_reader :number, :title

          def initialize(element, parent_node: nil)
            super
            add_child(AttributeValue, element, 'selected')
            @number = to_s[/([0-9]+\.)+[0-9]+|([0-9]+)/]
            @title = to_s[/[A-Z].*$/]
            similarity_methods :number, :title
          end

          def self.xpath
            'select'
          end
        end

        # Class for XCCDF profile
        class Profile < ElementWithId
          def initialize(element, parent_node: nil)
            super
            add_child(Title, element)
            add_child(Description, element)
            add_children(XccdfSelect, element)
            similarity_methods :id, :title, :level, :description, :xccdf_select
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

          def initialize(element, parent_node: nil)
            super
            @number = to_s[/group_([0-9]+\.)+[0-9]+|group_([0-9]+)/]&.gsub(/group_/, '')
            add_child(Title, element)
            add_child(Description, element)
            add_children(Group, element)
            add_children(Rule, element)
            similarity_methods :title, :number
          end

          def self.xpath
            'Group'
          end
        end

        # Class for XCCDF check-export
        class CheckExport < ElementBase
          def initialize(element, parent_node: nil)
            super
            add_child(AttributeValue, element, 'export-name')
            add_child(AttributeValue, element, 'value-id')
          end

          def self.xpath
            'check-export'
          end

          def eql?(other)
            to_s == other.to_s
          end

          def hash
            to_s.hash
          end

          def to_s
            [export_name.to_s, value_id.to_s].join('|')
          end
        end

        # Class for XCCDF check-content-ref
        class CheckContentRef < ElementBase
          def initialize(element, parent_node: nil)
            super
            add_child(AttributeValue, element, 'href')
            add_child(AttributeValue, element, 'name')
          end

          def self.xpath
            'check-content-ref'
          end

          def eql?(other)
            to_s == other.to_s
          end

          def hash
            to_s.hash
          end

          def to_s
            [href.to_s, name.to_s].join('|')
          end
        end

        # Class for XCCDF check
        class Check < ElementBase
          def initialize(element, parent_node: nil)
            super
            add_child(AttributeValue, element, 'system')
            add_children(CheckExport, element)
            add_children(CheckContentRef, element)
          end

          def eql?(other)
            @children.map(&:to_s).join == other.children.map(&:to_s).join
          end

          def hash
            @children.map(&:to_s).join.hash
          end

          def self.xpath
            'check'
          end
        end

        # Class for XCCDF Ident ControlURI element
        class ControlURI < ElementBase
          attr_reader :namespace, :value

          def initialize(element, parent_node: nil)
            super
            @namespace = element.attributes['controlURI'].namespace.prefix
            @value = element.attributes['controlURI'].value
          end

          def eql?(other)
            to_s == other.to_s
          end

          def hash
            to_s.hash
          end

          def to_s
            [label, @namespace, @value].join(':')
          end
        end

        # Class for XCCDF Ident System element
        class System < ElementBase
          attr_reader :system, :text

          def initialize(element, parent_node: nil)
            super
            @system = element.attributes['system'].value
            @text = element.text
          end

          def eql?(other)
            to_s == other.to_s
          end

          def hash
            to_s.hash
          end

          def to_s
            [label, @system, @text].join(':')
          end
        end

        # Class for XCCDF rule ident
        class Ident < ElementBase
          def initialize(element, parent_node: nil)
            super
            with_safe_methods { add_child(ControlURI, element) }
            with_safe_methods { add_child(System, element) }
          end

          def eql?(other)
            to_s == other.to_s
          end

          def hash
            to_s.hash
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

          def initialize(element, parent: nil, parent_node: nil)
            super
            add_child(AttributeValue, element, 'operator')
            add_children(Check, element)
          end

          def eql?(other)
            @children.map(&:to_s).join == other.children.map(&:to_s).join
          end

          def hash
            @children.map(&:to_s).join.hash
          end

          def self.xpath
            'complex-check'
          end
        end

        # Class for XCCDF rule metadata cis_controls framework safeguard
        class MetadataCisControlsFrameworkSafeguard < ElementBase
          def initialize(element, parent_node: nil)
            super
            add_child(ShortText, element['title'])
            add_child(ShortText, element['urn'])
            new_implementation_groups(element)
            add_child(ShortText, find_element.at_xpath(element, 'asset_type').text)
            add_child(ShortText, find_element.at_xpath(element, 'security_function').text)
          end

          def eql?(other)
            @children.map(&:to_s).join == other.children.map(&:to_s).join
          end

          def hash
            @children.map(&:hash).join.hash
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
            return if igroup.nil? || igroup.attributes.empty?

            add_child(ShortText, igroup['ig1']) if igroup['ig1']
            add_child(ShortText, igroup['ig2']) if igroup['ig2']
            add_child(ShortText, igroup['ig3']) if igroup['ig3']
          end
        end

        # Class for XCCDF rule metadata cis_controls framework
        class MetadataCisControlsFramework < ElementBase
          def initialize(element, parent_node: nil)
            super
            add_child(AttributeValue, element, 'urn')
            add_children(MetadataCisControlsFrameworkSafeguard, element)
          end

          def eql?(other)
            @children.map(&:to_s).join == other.children.map(&:to_s).join
          end

          def hash
            @children.map(&:hash).join.hash
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
          def initialize(element, parent: nil, parent_node: nil)
            super
            add_child(AttributeValue, element, 'controls')
            add_children(MetadataCisControlsFramework, element)
          end

          def eql?(other)
            @children.map(&:to_s).join == other.children.map(&:to_s).join
          end

          def hash
            @children.map(&:hash).join.hash
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
          def initialize(element, parent: nil, parent_node: nil)
            super
            add_children(MetadataCisControls, element)
          end

          def eql?(other)
            @children.map(&:to_s).join == other.children.map(&:to_s).join
          end

          def hash
            @children.map(&:hash).join.hash
          end

          def self.xpath
            'metadata'
          end
        end

        # Class for XCCDF Rule child element Rationale
        class Rationale < ElementBase
          def initialize(element, parent_node: nil)
            super
            add_child(LongText, element)
          end

          def eql?(other)
            to_s == other.to_s
          end

          def hash
            to_s.hash
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
          def initialize(element, parent_node: nil)
            super
            add_child(LongText, element)
          end

          def eql?(other)
            to_s == other.to_s
          end

          def hash
            to_s.hash
          end

          def self.xpath
            'fixtext'
          end

          def to_s
            text.to_s
          end
        end

        # Class for XCCDF rule
        class Rule < ElementWithId
          include AbideDevUtils::XCCDF::Parser::Objects::NumberedObject
          attr_reader :number

          def initialize(element, parent_node: nil)
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
            similarity_methods :number, :title
          end

          def self.xpath
            'Rule'
          end
        end

        # Class for XCCDF Value
        class Value < ElementWithId
          def initialize(element, parent_node: nil)
            super
            add_child(AttributeValue, element, 'operator')
            add_child(AttributeValue, element, 'type')
            add_child(Title, element)
            add_child(Description, element)
            add_child(ShortText, find_element.at_xpath(element, 'value'))
          end

          def <=>(other)
            return nil unless other.instance_of?(self.class)

            title.to_s <=> other.title.to_s
          end

          def eql?(other)
            operator.value == other.operator.value &&
              type.value == other.type.value &&
              title.to_s == other.title.to_s &&
              description.to_s == other.description.to_s &&
              text == other.text
          end

          def hash
            [
              operator.value,
              type.value,
              title.to_s,
              description.to_s,
              text,
            ].join.hash
          end

          def self.xpath
            'Value'
          end

          def to_s
            "#{title}: #{type.value} #{operator.value} #{text}"
          end
        end

        # Class for XCCDF benchmark status
        class Status < ElementBase
          def initialize(element, parent_node: nil)
            super
            add_child(ShortText, element)
            add_child(AttributeValue, element, 'date')
          end

          def eql?(other)
            to_s == other.to_s
          end

          def hash
            to_s.hash
          end

          def self.xpath
            'status'
          end

          def to_s
            [
              "Status:#{text}",
              "Date:#{date}",
            ].join('|')
          end
        end

        # Class for XCCDF benchmark version
        class Version < ElementBase
          def initialize(element, parent_node: nil)
            super
            add_child(ShortText, element)
          end

          def eql?(other)
            to_s == other.to_s
          end

          def hash
            to_s.hash
          end

          def self.xpath
            'version'
          end

          def to_s
            text.to_s
          end
        end

        # Class for XCCDF benchmark platform
        class Platform < ElementBase
          def initialize(element, parent_node: nil)
            super
            add_child(AttributeValue, element, 'idref')
          end

          def eql?(other)
            to_s == other.to_s
          end

          def hash
            to_s.hash
          end

          def self.xpath
            'platform'
          end

          def to_s
            idref.to_s
          end
        end

        # Class for XCCDF benchmark
        class Benchmark < ElementBase
          include AbideDevUtils::XCCDF::Parser::Objects::NumberedObject

          def initialize(element, parent_node: nil)
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

          def number
            @number ||= version.to_s[/([0-9]+\.)+[0-9]+/]
          end

          def to_h
            {
              title: title.to_s,
              version: version.to_s,
              status: status.to_s,
              platform: platform.to_s,
              profile: profile.map(&:to_h),
              group: group.map(&:to_h),
              value: value.map(&:to_h),
            }
          end

          def diff_only_rules(other, profile: nil, level: nil)
            self_rules = descendants.select { |x| x.is_a?(Rule) }
            other_rules = other.descendants.select { |x| x.is_a?(Rule) }
            unless profile.nil?
              self_rules = self_rules.select { |x| x.linked_profile.any? { |p| p.title.to_s.match?(profile) } }
            end
            unless level.nil?
              self_rules = self_rules.select { |x| x.linked_profile.any? { |p| p.level.to_s.match?(level) } }
            end
            diff_array_obj(self_rules, other_rules)
          end

          def self.xpath
            'Benchmark'
          end

          def to_s
            [title.to_s, version.to_s].join(' ')
          end
        end
      end
    end
  end
end
