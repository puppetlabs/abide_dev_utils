# frozen_string_literal: true

require 'json'
require 'pathname'
require 'yaml'
require 'puppet_pal'
require 'abide_dev_utils/ppt/class_utils'

module AbideDevUtils
  module Ppt
    class CoverageReport
      def self.generate(puppet_class_dir, hiera_path, profile = nil)
        coverage = {}
        coverage['classes'] = {}
        all_cap = ClassUtils.find_all_classes_and_paths(puppet_class_dir)
        invalid_classes = find_invalid_classes(all_cap)
        valid_classes = find_valid_classes(all_cap, invalid_classes)
        coverage['classes']['invalid'] = invalid_classes
        coverage['classes']['valid'] = valid_classes
        hiera = YAML.safe_load(File.open(hiera_path))
        profile&.gsub!(/^profile_/, '') unless profile.nil?

        matcher = profile.nil? ? /^profile_/ : /^profile_#{profile}/
        hiera.each do |k, v|
          key_base = k.split('::')[-1]
          coverage['benchmark'] = v if key_base == 'title'
          next unless key_base.match?(matcher)

          coverage[key_base] = generate_uncovered_data(v, valid_classes)
        end
        coverage
      end

      def self.generate_uncovered_data(ctrl_list, valid_classes)
        out_hash = {}
        out_hash[:num_total] = ctrl_list.length
        out_hash[:uncovered] = []
        out_hash[:covered] = []
        ctrl_list.each do |c|
          if valid_classes.include?(c)
            out_hash[:covered] << c
          else
            out_hash[:uncovered] << c
          end
        end
        out_hash[:num_covered] = out_hash[:covered].length
        out_hash[:num_uncovered] = out_hash[:uncovered].length
        out_hash[:coverage] = Float(
          (Float(out_hash[:num_covered]) / Float(out_hash[:num_total])) * 100.0
        ).floor(3)
        out_hash
      end

      def self.find_valid_classes(all_cap, invalid_classes)
        all_classes = all_cap.dup.transpose[0]
        return [] if all_classes.nil?

        return all_classes - invalid_classes unless invalid_classes.nil?

        all_classes
      end

      def self.find_invalid_classes(all_cap)
        invalid_classes = []
        all_cap.each do |cap|
          invalid_classes << cap[0] unless class_valid?(cap[1])
        end
        invalid_classes
      end

      def self.class_valid?(manifest_path)
        compiler = Puppet::Pal::Compiler.new(nil)
        ast = compiler.parse_file(manifest_path)
        ast.body.body.statements.each do |s|
          next unless s.respond_to?(:arguments)
          next unless s.arguments.respond_to?(:each)

          s.arguments.each do |i|
            return false if i.value == 'Not implemented'
          end
        end
        true
      end
    end
  end
end
