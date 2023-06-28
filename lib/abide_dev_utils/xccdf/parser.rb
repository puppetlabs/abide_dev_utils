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

          rules = benchmark.descendants.select { |d| d.label == 'rule' }
          benchmark.profile.each do |profile|
            profile.xccdf_select.each do |sel|
              rules.select { |rule| rule.id.value == sel.idref.value }.each do |rule|
                rule.add_link(profile)
                profile.add_link(rule)
              end
            end
          end
        end

        def self.link_rule_values(benchmark)
          return unless benchmark.respond_to?(:value)

          rules = benchmark.descendants.select { |d| d.label == 'rule' }
          benchmark.value.each do |value|
            rule = rules.find { |r| r.title.to_s == value.title.to_s }
            next unless rule

            rule.add_link(value)
            value.add_link(rule)
          end
        end
      end
    end
  end
end
