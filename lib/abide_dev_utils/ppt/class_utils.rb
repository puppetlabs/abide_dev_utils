# frozen_string_literal: true

require 'fileutils'
require 'tempfile'
require 'abide_dev_utils/errors/ppt'

module AbideDevUtils
  module Ppt
    module ClassUtils
      include AbideDevUtils::Errors::Ppt

      CLASS_NAME_PATTERN = /\A([a-z][a-z0-9_]*)?(::[a-z][a-z0-9_]*)*\Z/.freeze
      CLASS_NAME_CAPTURE_PATTERN = /\A^class (?<class_name>([a-z][a-z0-9_]*)?(::[a-z][a-z0-9_]*)*).*\Z/.freeze

      # Validates a Puppet class name
      # @param name [String] Puppet class name
      # @return [Boolean] Is the name a valid Puppet class name
      def self.valid_class_name?(name)
        name.match?(CLASS_NAME_PATTERN)
      end

      # Takes a full Puppet class name and returns the path
      # of the class file. This command must be run from the
      # root module directory if validate_path is true.
      # @param class_name [String] full Puppet class name
      # @return [String] path to class file
      def self.path_from_class_name(class_name)
        parts = class_name.split('::')
        parts[-1] = "#{parts[-1]}.pp"
        File.expand_path(File.join('manifests', parts[1..-1]))
      end

      # Returns the namespaced class name from a file path
      # @param class_path [String] the path to the Puppet class
      # @return [String] the namespaced class name
      def self.class_name_from_path(class_path)
        parts = class_path.split(File::SEPARATOR).map { |x| x == '' ? File::SEPARATOR : x }
        module_root_idx = parts.find_index('manifests') - 1
        module_root = parts[module_root_idx].split('-')[-1]
        namespaces = parts[(module_root_idx + 2)..-2].join('::') # add 2 to module root idx to skip manifests dir
        class_name = parts[-1].delete_suffix('.pp')
        [module_root, namespaces, class_name].join('::')
      end

      # Takes a path to a Puppet file and extracts the class name from the class declaration in the file.
      # This differs from class_name_from_path because we actually read the class file and search
      # the code for a class declaration to get the class name instead of just using the path
      # to construct a valid Puppet class name.
      # @param path [String] the path to a Puppet file
      # @return [String] the Puppet class name
      # @raise [ClassDeclarationNotFoundError] if there is not class declaration in the file
      def self.class_name_from_declaration(path)
        File.readlines(path).each do |line|
          next unless line.match?(/^class /)

          return CLASS_NAME_CAPTURE_PATTERN.match(line)['class_name']
        end
        raise ClassDeclarationNotFoundError, "Path:#{path}"
      end

      # Renames a file by file move. Ensures destination path exists before moving.
      # @param from_path [String] path of the original file
      # @param to_path [String] path of the new file
      # @param verbose [Boolean] Sets verbose mode on file operations
      # @param force [Boolean] If true, file move file overwrite existing files
      def self.rename_class_file(from_path, to_path, **kwargs)
        verbose = kwargs.fetch(:verbose, false)
        force = kwargs.fetch(:force, false)
        FileUtils.mkdir_p(File.dirname(to_path), verbose: verbose)
        FileUtils.mv(from_path, to_path, verbose: verbose, force: force)
      end

      # Renames a Puppet class in the class declaration of the given file
      # @param from [String] the original class name
      # @param to [String] the new class name
      # @param file_path [String] the path to the class file
      # @param verbose [Boolean] Sets verbose mode on file operations
      # @param force [Boolean] If true, file move file overwrite existing files
      # @raise [ClassDeclarationNotFoundError] if the class file does not contain the from class declaration
      def self.rename_puppet_class_declaration(from, to, file_path, **kwargs)
        verbose = kwargs.fetch(:verbose, false)
        force = kwargs.fetch(:force, false)
        temp_file = Tempfile.new
        renamed = false
        begin
          File.readlines(file_path).each do |line|
            if line.match?(/^class #{from}.*/)
              line.gsub!(/^class #{from}/, "class #{to}")
              renamed = true
            end
            temp_file.puts line
          end
          raise ClassDeclarationNotFoundError, "File:#{file_path},Declaration:class #{from}" unless renamed

          temp_file.close
          FileUtils.mv(temp_file.path, file_path, verbose: verbose, force: force)
        ensure
          temp_file.close
          temp_file.unlink
        end
      end

      # Determines if a Puppet class name is mismatched by constructing a class name from
      # a path to a Puppet file and extracting the class name from the class declaration
      # inside the file. This is useful to determine if a Puppet class file breaks the
      # autoload path pattern.
      # @param path [String] path to a Puppet class file
      # @return [Boolean] if the actual class name and path-constructed class name match
      def self.mismatched_class_declaration?(path)
        class_name_from_path(path) != class_name_from_declaration(path)
      end

      # Finds all Puppet classes in the given directory that have class declarations
      # that do not adhere to the autoload path pattern.
      # @param class_dir [String] path to a directory containing Puppet class files
      # @return [Array] paths to all Puppet class files with mismatched class names
      def self.find_all_mismatched_class_declarations(class_dir)
        mismatched = []
        Dir[File.join(File.expand_path(class_dir), '*.pp')].each do |class_file|
          mismatched << class_file if mismatched_class_declaration?(class_file)
        end
        mismatched.sort
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
    end
  end
end
