# frozen_string_literal: true

require 'abide_dev_utils/files'
require 'abide_dev_utils/xccdf/parser/objects'

module AbideDevUtils
  module XCCDF
    # Contains methods and classes for parsing XCCDF files,
    module Parser
      def self.parse(file_path)
        doc = AbideDevUtils::Files::Reader.read(file_path)
        doc.remove_namespaces!
        benchmark = AbideDevUtils::XCCDF::Parser::Objects::Benchmark.new(doc)
        Linker.resolve_links(benchmark)
        benchmark
      end

      # Links XCCDF objects by reference.
      # Each link is resolved and then a bidirectional link is established
      # between the two objects.
      module Linker
        def self.resolve_links(benchmark)
          link_profile_rules(benchmark)
          link_rule_values(benchmark)
        end

        def self.link_profile_rules(benchmark)
          return unless benchmark.respond_to?(:profile)

          rules = benchmark.find_children_by_class(AbideDevUtils::XCCDF::Parser::Objects::Rule, recurse: true)
          benchmark.profile.each do |profile|
            profile.xccdf_select.each do |sel|
              rules.select { |rule| rule.id == sel.idref }.each do |rule|
                rule.add_link(profile)
                profile.add_link(rule)
              end
            end
          end
        end

        def self.link_rule_values(benchmark)
          return unless benchmark.respond_to?(:value)

          rules = benchmark.find_children_by_class(AbideDevUtils::XCCDF::Parser::Objects::Rule, recurse: true)
          benchmark.value.each do |value|
            rules.each do |rule|
              unless rule.find_children_by_attribute_value('value-id', value.id, recurse: true).empty?
                rule.add_link(value)
                value.add_link(rule)
              end
            end
          end
        end
      end
    end
  end
end
