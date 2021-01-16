# frozen_string_literal: true

require 'json'
require 'pathname'
require 'yaml'
require 'puppet_pal'

module AbideDevUtils
  module Ppt
    def self.coverage_report(puppet_class_dir, hiera_path, profile = nil)
      coverage = {}
      coverage['classes'] = {}
      all_cap = find_all_classes_and_paths(puppet_class_dir)
      invalid_classes = find_invalid_classes(all_cap)
      valid_classes = all_cap.dup.transpose[0] - invalid_classes
      coverage['classes']['invalid'] = invalid_classes
      coverage['classes']['valid'] = valid_classes
      hiera = YAML.safe_load(File.open(hiera_path))
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

    # Given a directory holding Puppet manifests, returns
    # the full namespace for all classes in that directory.
    # @param puppet_class_dir [String] path to a dir containing Puppet manifests
    # @return [String] The namespace for all classes in manifests in the dir
    def self.find_class_namespace(puppet_class_dir)
      path = Pathname.new(puppet_class_dir)
      mod_root = nil
      ns_parts = []
      found_manifests = false
      path.ascend do |p|
        if found_manifests
          mod_root = find_mod_root(p)
          break
        end
        if File.basename(p) == 'manifests'
          found_manifests = true
          next
        else
          ns_parts << File.basename(p)
        end
      end
      "#{mod_root}::#{ns_parts.reverse.join('::')}::"
    end

    # Given a Pathname object of the 'manifests' directory in a Puppet module,
    # determines the module namespace root. Does this by consulting
    # metadata.json, if it exists, or by using the parent directory name.
    # @param pathname [Pathname] A Pathname object of the module's manifests dir
    # @return [String] The module's namespace root
    def self.find_mod_root(pathname)
      metadata_file = nil
      pathname.entries.each do |e|
        metadata_file = "#{pathname}/metadata.json" if File.basename(e) == 'metadata.json'
      end
      if metadata_file.nil?
        File.basename(p)
      else
        File.open(metadata_file) do |f|
          file = JSON.parse(f.read)
          File.basename(p) unless file.key?('name')
          file['name'].split('-')[-1]
        end
      end
    end

    # @return [Array] An array of frozen arrays where each sub-array's
    #   index 0 is class_name and index 1 is the full path to the file.
    def self.find_all_classes_and_paths(puppet_class_dir)
      all_cap = []
      Dir.each_child(puppet_class_dir) do |c|
        path = "#{puppet_class_dir}/#{c}"
        next if File.directory?(path) || File.extname(path) != '.pp'

        all_cap << [File.basename(path, '.pp'), path].freeze
      end
      all_cap
    end

    def self.find_valid_classes(all_cap)
      all_classes = all_cap.dup.transpose[0]
      all_classes - find_invalid_classes(all_cap)
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
