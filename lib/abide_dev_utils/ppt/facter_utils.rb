# frozen_string_literal: true

require 'json'
require 'facterdb'

module AbideDevUtils
  module Ppt
    # Methods relating to Facter
    module FacterUtils
      class << self
        attr_writer :current_version

        def current_version
          return latest_version unless defined?(@current_version)

          @current_version
        end

        def use_version(version)
          self.current_version = version
          current_version
        end

        def with_version(version, reset: true)
          return unless block_given?

          old_ver = current_version.dup
          use_version(version)
          output = yield
          use_version(old_ver) if reset
          output
        end

        def fact_files
          @fact_files ||= FacterDB.facterdb_fact_files.each_with_object({}) do |f, h|
            facter_version = file_facter_version(f)
            h[facter_version] = [] unless h.key?(facter_version)
            h[facter_version] << f
          end
        end

        def fact_sets(facter_version: current_version)
          @fact_sets ||= fact_files[facter_version].each_with_object({}) do |fp, h|
            h[facter_version] = [] unless h.key?(facter_version)
            h[facter_version] << JSON.parse(File.read(fp))
          end
        end

        def file_facter_version(path)
          File.basename(File.dirname(path))
        end

        def all_versions
          @all_versions ||= fact_files.keys.sort
        end

        def latest_version
          @latest_version ||= all_versions[-1]
        end

        def previous_major_version(facter_version = current_version)
          @previous_major_version_map ||= {}

          majver = facter_version.split('.')[0]
          return @previous_major_version_map[majver] if @previous_major_version_map.key?(majver)

          prev_majver = (majver.to_i - 1).to_s
          prev_ver = all_versions.select { |v| v.start_with?(prev_majver) }.max
          return nil if prev_ver.to_i < 1

          @previous_major_version_map[majver] = prev_ver
          @previous_major_version_map[majver]
        end

        def recurse_versions(version = current_version, &block)
          use_version(version)
          output = yield
          return output unless output.nil? || output.empty?

          prev_ver = previous_major_version(version).dup
          return nil if prev_ver.nil?

          recurse_versions(prev_ver, &block)
        rescue SystemStackError
          locals = {
            prev_ver_map: @previous_major_version_map,
            current_version: current_version,
          }
          raise "Failed to find output while recursing versions. Locals: #{locals}"
        end

        def recursive_facts_for_os(os_name, os_release_major = nil, os_hardware: 'x86_64')
          saved_ver = current_version.dup
          output = recurse_versions do
            facts_for_os(os_name, os_release_major, os_hardware: os_hardware)
          end
          use_version(saved_ver)
          output
        end

        def facts_for_os(os_name, os_release_major = nil, os_hardware: 'x86_64', facter_version: current_version)
          cache_key = "#{os_name.downcase}_#{os_release_major}_#{os_hardware}"
          return @facts_for_os[cache_key] if @facts_for_os&.key?(cache_key)

          fact_file = fact_files[facter_version].find do |f|
            name_parts = File.basename(f, '.facts').split('-')
            name = name_parts[0]
            relmaj = name_parts.length >= 3 ? name_parts[1] : nil
            hardware = name_parts[-1]
            name == os_name.downcase && relmaj == os_release_major && hardware == os_hardware
          end
          return if fact_file.nil? || fact_file.empty?

          @facts_for_os = {} unless defined?(@facts_for_os)
          @facts_for_os[cache_key] = JSON.parse(File.read(fact_file))
          @facts_for_os[cache_key]
        end

        def resolve_dot_path(dot_path, facter_version: latest_version)
          path_array = dot_path.delete_prefix('facts.').split('.')
          resolved = fact_sets[facter_version].map do |fs|
            fs.dig(*path_array)
          end
          resolved.compact.uniq
        end

        def resolve_related_dot_paths(*dot_paths, facter_version: current_version)
          resolved = []
          fact_sets[facter_version].map do |fs|
            resolved << dot_paths.map do |p|
              path_array = p.delete_prefix('facts.').split('.')
              fs.dig(*path_array)
            end
          end
          resolved
        end
      end
    end
  end
end
