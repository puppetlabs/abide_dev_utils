# frozen_string_literal: true

require 'abide_dev_utils/ppt/coverage'
require 'abide_dev_utils/ppt/new_obj'

module AbideDevUtils
  module Ppt
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
  end
end
