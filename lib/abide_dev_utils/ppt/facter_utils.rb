# frozen_string_literal: true

require 'json'
require 'facterdb'
require_relative '../dot_number_comparable'

module AbideDevUtils
  module Ppt
    # Methods relating to Facter
    module FacterUtils
      # A set of facts for a specific Facter version
      class FactSet
        include AbideDevUtils::DotNumberComparable

        attr_reader :facter_version, :facts

        def initialize(facter_version)
          @facter_version = facter_version.to_s
          @facts = []
        end
        alias number facter_version # for DotNumberComparable

        def load_facts(fact_file)
          @facts << JSON.parse(File.read(fact_file))
        end

        def find_by_fact_value_tuples(*fact_val_tuples)
          facts.each do |f|
            results = fact_val_tuples.each_with_object([]) do |fvt, ary|
              ary << true if f.dig(*fvt[0].delete_prefix('facts').split('.')) == fvt[1]
            end
            return f if results.size == fact_val_tuples.size
          end
          nil
        end

        def find_by_fact_value_tuple(fact_val_tuple)
          fact_name, fact_val = fact_val_tuple
          @facts.find { |f| f.dig(*fact_name.delete_prefix('facts').split('.')) == fact_val }
        end

        def dot_dig(dot_path)
          result = @facts.map { |f| f.dig(*dot_path.delete_prefix('facts').split('.')) }
          return nil if result.empty?

          result
        end

        def dig(*args)
          result = @facts.map { |f| f.dig(*args) }
          return nil if result.empty?

          result
        end
      end

      class FactSets
        REQUIRED_FACTERDB_VERSION = '1.21.0'

        def initialize
          check_facterdb_version
          @fact_val_tuple_cache = {}
          @dot_dig_cache = {}
          @dot_dig_related_cache = {}
        end

        def fact_sets
          external_fact_path = File.expand_path(File.join(__dir__, '../../../files/fact_sets'))
          all_facts = (FacterDB.default_fact_files + FacterDB.external_fact_files(external_fact_path)).uniq
          @fact_sets ||= all_facts.each_with_object({}) do |f, h|
            facter_version = File.basename(File.dirname(f))
            fact_set = h[facter_version] || FactSet.new(facter_version)
            fact_set.load_facts(f)
            h[facter_version] = fact_set unless h.key?(facter_version)
          end
        end

        def fact_set(facter_version)
          fact_sets[facter_version]
        end

        def facter_versions
          @facter_versions ||= fact_sets.keys.sort
        end

        def find_by_fact_value_tuples(*fact_val_tuples)
          fact_sets.each do |_, fs|
            result = fs.find_by_fact_value_tuples(*fact_val_tuples)
            return result unless result.nil? || result.empty?
          end
          nil
        end

        def find_by_fact_value_tuple(fact_val_tuple)
          ck = cache_key(*fact_val_tuple)
          return @fact_val_tuple_cache[ck] if @fact_val_tuple_cache.key?(ck)

          facter_versions.each do |v|
            result = fact_set(v).find_by_fact_value_tuple(fact_val_tuple)
            next if result.nil? || result.empty?

            @fact_val_tuple_cache[ck] = result
            return result
          end

          @fact_val_tuple_cache[ck] = nil
        end

        def dot_dig(dot_path, facter_version: latest_version, recurse: true)
          ck = cache_key(dot_path, facter_version, recurse)
          return @dot_dig_cache[ck] if @dot_dig_cache.key?(ck)

          result = fact_set(facter_version).dot_dig(dot_path)
          unless result.nil? && recurse
            @dot_dig_cache[ck] = result
            return result
          end

          previous = previous_version(facter_version)
          unless previous
            @dot_dig_cache[ck] = result
            return result
          end

          result = dot_dig(dot_path, facter_version: previous, recurse: true)
          @dot_dig_cache[ck] = result
          result
        end
        alias resolve_dot_path dot_dig

        def dot_dig_related(*dot_paths, facter_version: latest_version, recurse: true)
          ck = cache_key(*dot_paths, facter_version, recurse)
          return @dot_dig_related_cache[ck] if @dot_dig_related_cache.key?(ck)

          result = []
          fact_sets[facter_version].facts.map do |f|
            result << dot_paths.map { |p| f.dig(*p.delete_prefix('facts').split('.')) }
          end
          unless recurse
            @dot_dig_related_cache[ck] = result.compact.uniq
            return @dot_dig_related_cache[ck]
          end

          previous = previous_version(facter_version)
          unless previous
            @dot_dig_related_cache[ck] = result.compact.uniq
            return @dot_dig_related_cache[ck]
          end

          res = result + dot_dig_related(*dot_paths, facter_version: previous, recurse: true)
          @dot_dig_related_cache[ck] = res.compact.uniq
          @dot_dig_related_cache[ck]
        end
        alias resolve_related_dot_paths dot_dig_related

        private

        def check_facterdb_version
          require 'facterdb/version'
          return if Gem::Version.new(FacterDB::Version::STRING) >= Gem::Version.new(REQUIRED_FACTERDB_VERSION)

          warn "FacterDB version #{FacterDB::Version::STRING} is too old. Please upgrade to 1.21.0 or later."
          warn 'FacterUtils may not work correctly or at all.'
        end

        def cache_key(*args)
          args.map(&:to_s).join('_')
        end

        def latest_version
          facter_versions.last
        end

        def previous_version(facter_version)
          index = facter_versions.index(facter_version)
          return unless index&.positive?

          facter_versions[index - 1]
        end
      end

      class << self
        # attr_writer :current_version

        # def current_version
        #   return latest_version unless defined?(@current_version)

        #   @current_version
        # end

        # def use_version(version)
        #   self.current_version = version
        #   current_version
        # end

        # def with_version(version, reset: true)
        #   return unless block_given?

        #   old_ver = current_version.dup
        #   use_version(version)
        #   output = yield
        #   use_version(old_ver) if reset
        #   output
        # end

        # def fact_files
        #   FacterDB.facterdb_fact_files.each_with_object({}) do |f, h|
        #     facter_version = file_facter_version(f)
        #     h[facter_version] = [] unless h.key?(facter_version)
        #     h[facter_version] << f
        #   end
        # end

        # def fact_sets(facter_version: current_version)
        #   fact_files[facter_version].each_with_object({}) do |fp, h|
        #     h[facter_version] = [] unless h.key?(facter_version)
        #     h[facter_version] << JSON.parse(File.read(fp))
        #   end
        # end

        # def file_facter_version(path)
        #   File.basename(File.dirname(path))
        # end

        # def all_versions
        #   fact_files.keys.sort
        # end

        # def latest_version
        #   all_versions[-1]
        # end

        def fact_sets
          external_fact_path = File.expand_path(File.join(__dir__, '../../../files/fact_sets'))
          all_facts = (FacterDB.default_fact_files + FacterDB.external_fact_files(external_fact_path)).uniq
          @fact_sets ||= all_facts.each_with_object([]) do |f, ary|
            facter_version = File.basename(File.dirname(f))
            fact_set = ary.find { |fs| fs.facter_version == facter_version }
            fact_set ||= FactSet.new(facter_version)
            fact_set.load_facts(f)
            ary << fact_set unless ary.include?(fact_set)
          end
        end

        def all_versions
          @all_versions ||= fact_sets.sort.map(&:facter_version)
        end

        def latest_version
          @latest_version ||= all_versions.last
        end

        def with_version(version)
          return unless block_given?

          fact_set = fact_sets.find { |fs| fs.facter_version == version }
          raise "No facts found for version #{version}" unless fact_set

          yield fact_set
        end

        def previous_major_version(facter_version = latest_version)
          majver = facter_version.split('.')[0]
          prev_majver = (majver.to_i - 1).to_s
          prev_ver = all_versions.select { |v| v.start_with?(prev_majver) }.max
          return nil if prev_ver.to_i < 1

          prev_ver
        end

        def previous_version(facter_version = latest_version)
          reversed = all_versions.reverse
          rev_index = reversed.index(facter_version)
          return nil if rev_index.nil? || rev_index == reversed.length - 1

          reversed[reversed.index(facter_version) + 1]
        end

        def recurse_versions(version = latest_version, &block)
          output = yield version
          return output unless output.nil? || output.empty?

          prev_ver = previous_version(version).dup
          return nil if prev_ver.nil?

          recurse_versions(prev_ver, &block)
        rescue SystemStackError
          locals = {
            prev_ver_map: @previous_major_version_map,
            current_version: current_version
          }
          raise "Failed to find output while recursing versions. Locals: #{locals}"
        end

        def recursive_facts_for_os(os_name, os_release_major = nil, facter_version: latest_version)
          recurse_versions(facter_version) do |ver|
            facts_for_os(os_name, os_release_major, facter_version: ver)
          end
        end

        # def facts_for_os(os_name, os_release_major = nil, facter_version: latest_version)
        #   fact_sets..find do |f|
        #     f['os']['name'] == os_name && f['os']['release']['major'] == os_release_major.to_s
        #   end
        # end

        def resolve_dot_path(dot_path, facter_version: latest_version, strict: false)
          path_array = dot_path.delete_prefix('facts.').split('.')
          resolved = if strict
                       fact_sets[facter_version].map do |fs|
                         fs.dig(*path_array)
                       end
                     else
                       recurse_versions(facter_version) do |ver|
                         fact_sets[ver].map { |fs| fs.dig(*path_array) }
                       end
                     end
          resolved&.compact&.uniq
        end

        def resolve_related_dot_paths(*dot_paths, facter_version: latest_version, strict: false)
          resolved = []
          if strict
            fact_sets[facter_version].map do |fs|
              resolved << dot_paths.map do |p|
                path_array = p.delete_prefix('facts.').split('.')
                fs.dig(*path_array)
              end
            end
          else
            recurse_versions(facter_version) do |ver|
              fact_sets[ver].map do |fs|
                resolved << dot_paths.map do |p|
                  path_array = p.delete_prefix('facts.').split('.')
                  fs.dig(*path_array)
                end
              end
            end
          end
          resolved
        end
      end
    end
  end
end
