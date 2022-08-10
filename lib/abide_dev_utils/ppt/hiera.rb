# frozen_string_literal: true

require 'yaml'
require 'abide_dev_utils/validate'
require 'abide_dev_utils/ppt/facter_utils'

module AbideDevUtils
  module Ppt
    # Module for working with Hiera
    module Hiera
      INTERP_PATTERN = /%{([^{}]+)}/.freeze
      FACT_PATTERN = /%{facts\.([^{}]+)}/.freeze
      DEFAULT_FACTER_VERSION = '3.14'
      DEFAULT_CONFIG_FILE = 'hiera.yaml'

      def self.facter_version=(version)
        @facter_version = AbideDevUtils::Ppt::FacterUtils.use_version(version.to_s)
      end

      def self.facter_version
        @facter_version
      end

      def self.default_datadir=(dir)
        edir = File.expand_path(dir)
        raise "Dir #{edir} not found" unless File.directory?(edir)

        @default_datadir = edir
      end

      def self.default_datadir
        @default_datadir
      end

      # Represents a Hiera configuration file
      class Config
        def initialize(path = DEFAULT_CONFIG_FILE, facter_version: DEFAULT_FACTER_VERSION)
          @path = File.expand_path(path)
          raise "Hiera config file at path #{@path} not found!" unless File.file?(@path)

          @root_dir = File.dirname(@path)
          @conf = YAML.load_file(File.expand_path(path))
          @by_name_path_store = {}
          AbideDevUtils::Ppt::Hiera.facter_version = facter_version
          if @conf['defaults'].key?('datadir')
            AbideDevUtils::Ppt::Hiera.default_datadir = File.join(@root_dir, @conf['defaults']['datadir'])
          end
        end

        def hierarchy
          @hierarchy ||= Hierarchy.new(@conf['hierarchy'], AbideDevUtils::Ppt::Hiera.default_datadir)
        end

        def version
          @version ||= @conf['version']
        end

        def defaults
          @defaults ||= @conf['defaults']
        end

        def default_datadir
          AbideDevUtils::Ppt::Hiera.default_datadir
        end

        def default_data_hash
          @default_data_hash ||= defaults['data_hash']
        end

        def local_hiera_files(hierarchy_name: nil)
          if hierarchy_name
            hierarchy.entry_by_name(hierarchy_name).local_files
          else
            hierarchy.entries.map(&:local_files).flatten
          end
        end

        def local_hiera_files_with_fact(fact_str, value = nil, hierarchy_name: nil)
          if hierarchy_name
            hierarchy.entry_by_name(hierarchy_name).local_files_with_fact(fact_str, value)
          else
            hierarchy.entries.map { |e| e.local_files_with_fact(fact_str, value) }.flatten
          end
        end

        def local_hiera_files_with_facts(*fact_arrays, hierarchy_name: nil)
          if hierarchy_name
            hierarchy.entry_by_name(hierarchy_name).local_files_with_facts(*fact_arrays)
          else
            hierarchy.entries.map { |e| e.local_files_with_fact(*fact_arrays) }.flatten
          end
        end
      end

      # Represents the "hierarchy" section of the Hiera config
      class Hierarchy
        attr_reader :default_datadir, :entries

        def initialize(hierarchy, default_datadir)
          @hierarchy = hierarchy
          @default_datadir = File.expand_path(default_datadir)
          @entries = @hierarchy.map { |h| HierarchyEntry.new(h) }
          @by_name_store = {}
          @paths_by_name_store = {}
        end

        def method_missing(m, *args, &block)
          if %i[each each_with_object each_with_index select reject map].include?(m)
            @entries.send(m, *args, &block)
          else
            super
          end
        end

        def respond_to_missing?(m, include_private = false)
          %i[each each_with_object each_with_index select reject map].include?(m) || super
        end

        def entry_by_name(name)
          AbideDevUtils::Validate.populated_string(name)
          return @by_name_store[name] if @by_name_store[name]

          found = @entries.select { |x| x.name == name }
          AbideDevUtils::Validate.not_empty(found, "Hierarchy entry for name '#{name}' not found")
          @by_name_store[name] = found[0]
          @by_name_store[name]
        end
      end

      # Represents a single entry in the hierarchy
      class HierarchyEntry
        attr_reader :entry, :name, :paths

        def initialize(entry)
          @entry = entry
          @name = @entry['name']
          @paths = @entry.key?('path') ? create_paths(@entry['path']) : create_paths(*@entry['paths'])
        end

        def local_files
          @local_files ||= paths.map(&:local_files).flatten
        end

        def local_files_with_fact(fact_str, value = nil)
          paths.map { |p| p.local_files_with_fact(fact_str, value) }.flatten
        end

        def local_files_with_facts(*fact_arrays)
          paths.map { |p| p.local_files_with_facts(*fact_arrays) }.flatten
        end

        def to_s
          name
        end

        private

        def create_paths(*paths)
          paths.map { |p| HierarchyEntryPath.new(p) }
        end
      end

      # Represents a Hiera entry path
      class HierarchyEntryPath
        attr_reader :path

        def initialize(path)
          @path = path
        end

        def path_parts
          @path_parts ||= path.split('/')
        end

        def interpolation
          @interpolation ||= path.scan(INTERP_PATTERN).flatten
        end

        def interpolation?
          !interpolation.empty?
        end

        def facts
          @facts ||= path.scan(FACT_PATTERN).flatten
        end

        def facts?
          !facts.empty?
        end

        def possible_fact_values
          @possible_fact_values ||= AbideDevUtils::Ppt::FacterUtils.resolve_related_dot_paths(*facts)
        end

        def local_files
          @local_files ||= find_local_files.flatten
        end

        def local_files_with_fact(fact_str, value = nil)
          local_files.select do |lf|
            # The match below is case-insentive for convenience
            (value.nil? ? lf.fact_values.key?(fact_str) : (lf.fact_values[fact_str]&.match?(/#{value}/i) || false))
          end
        end

        def local_files_with_facts(*fact_arrays)
          return local_files_with_fact(*fact_arrays[0]) if fact_arrays.length == 1

          start_fact = fact_arrays[0][0]
          last_fact = nil
          memo = {}
          with_facts = []
          fact_arrays.each do |fa|
            cur_fact = fa[0]
            memo[cur_fact] = local_files_with_fact(*fa)
            if cur_fact == start_fact
              with_facts = memo[cur_fact]
            else
              last_paths = memo[last_fact].map(&:path)
              cur_paths = memo[cur_fact].map(&:path)
              with_facts.reject! { |x| last_paths.difference(cur_paths).include?(x.path) }
            end
            last_fact = cur_fact
          end
          with_facts.flatten.uniq(&:path)
        end

        def to_s
          path
        end

        private

        def find_local_files
          new_paths = []
          possible_fact_values.each do |pfv|
            new_path = path.dup
            pfv.each do |v|
              next unless v

              new_path.sub!(FACT_PATTERN, v)
            end
            new_paths << EntryPathLocalFile.new(new_path, facts, possible_fact_values)
          end
          new_paths.uniq(&:path).select(&:exist?)
        end
      end

      # Represents a local file derived from a Hiera path
      class EntryPathLocalFile
        attr_reader :path, :facts

        def initialize(path, facts, possible_fact_values)
          @path = File.expand_path(File.join(AbideDevUtils::Ppt::Hiera.default_datadir, path))
          @facts = facts
          @possible_fact_values = possible_fact_values
        end

        def fact_values
          @fact_values ||= fact_values_for_path
        end

        def path_parts
          @path_parts ||= path.split('/')
        end

        def exist?
          File.file?(path)
        end

        def to_s
          path
        end

        def to_h
          {
            path: path,
            facts: facts
          }
        end

        private

        def fact_values_for_path
          no_fext_path_parts = path_parts.map { |part| File.basename(part, '.yaml') }
          valid_fact_values = @possible_fact_values.select do |pfv|
            pfv.all? { |v| no_fext_path_parts.include?(v) }
          end
          valid_fact_values.uniq! # Removes duplicate arrays, not duplicate fact values
          valid_fact_values.flatten!
          return {} if valid_fact_values.empty?

          fact_vals = {}
          facts.each_index { |idx| fact_vals[facts[idx]] = valid_fact_values[idx] }
          fact_vals
        end
      end
    end
  end
end
