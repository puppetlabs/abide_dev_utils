# frozen_string_literal: true

require 'json'
require 'facterdb'

module AbideDevUtils
  module Ppt
    # Methods relating to Facter
    module FacterUtils
      class << self
        def use_version(version)
          @use_version = version
          @use_version
        end

        def fact_sets(facter_version: @use_version || latest_version)
          @fact_sets ||= fact_files[facter_version].each_with_object({}) do |fp, h|
            h[facter_version] = [] unless h.key?(facter_version)
            h[facter_version] << JSON.parse(File.read(fp))
          end
        end

        def fact_files
          @fact_files ||= FacterDB.facterdb_fact_files.each_with_object({}) do |f, h|
            facter_version = file_facter_version(f)
            h[facter_version] = [] unless h.key?(facter_version)
            h[facter_version] << f
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

        def resolve_dot_path(dot_path, facter_version: latest_version)
          path_array = dot_path.delete_prefix('facts.').split('.')
          resolved = fact_sets[facter_version].map do |fs|
            fs.dig(*path_array)
          end
          resolved.compact.uniq
        end

        def resolve_related_dot_paths(*dot_paths, facter_version: @use_version || latest_version)
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
