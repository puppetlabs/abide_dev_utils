# frozen_string_literal: true

require 'pathname'
require 'metadata_json_lint'
require 'puppet-lint'
require 'json'

module AbideDevUtils
  module Ppt
    class ScoreModule
      attr_reader :module_name, :module_dir, :manifests_dir

      def initialize(module_dir)
        @module_name = module_dir.split(File::SEPARATOR)[-1]
        @module_dir = real_module_dir(module_dir)
        @manifests_dir = File.join(real_module_dir(module_dir), 'manifests')
        @metadata = JSON.parse(File.join(@module_dir, 'metadata.json'))
      end

      def lint
        linter_exit_code, linter_output = lint_manifests
        {
          exit_code: linter_exit_code,
          manifests: manifest_count,
          lines: line_count,
          linter_version: linter_version,
          output: linter_output
        }.to_json
      end

      # def metadata

      # end

      private

      def manifests
        @manifests ||= Dir["#{manifests_dir}/**/*.pp"]
      end

      def manifest_count
        @manifest_count ||= manifests.count
      end

      def line_count
        @line_count ||= manifests.each_with_object([]) { |x, ary| ary << File.readlines(x).size }.sum
      end

      def lint_manifests
        results = []
        PuppetLint.configuration.with_filename = true
        PuppetLint.configuration.json = true
        PuppetLint.configuration.relative = true
        linter_exit_code = 0
        manifests.each do |manifest|
          next if PuppetLint.configuration.ignore_paths.any? { |p| File.fnmatch(p, manifest) }

          linter = PuppetLint.new
          linter.file = manifest
          linter.run
          linter_exit_code = 1 if linter.errors? || linter.warnings?
          results << linter.problems.reject { |x| x[:kind] == :ignored }
        end
        [linter_exit_code, JSON.generate(results)]
      end

      def lint_metadata
        results = { errors: [], warnings: [] }
        results[:errors] << metadata_schema_errors
        dep_errors, dep_warnings = metadata_validate_deps
        results[:errors] << dep_errors
        results[:warnings] << dep_warnings
        results[:errors] << metadata_deprecated_fields
      end

      def metadata_schema_errors
        MetadataJsonLint::Schema.new.validate(@metadata).each_with_object([]) do |err, ary|
          check = err[:field] == 'root' ? :required_fields : err[:field]
          ary << metadata_err(check, err[:message])
        end
      end

      def metadata_validate_deps
        return [[], []] unless @metadata.key?('dependencies')

        errors, warnings = []
        duplicates = metadata_dep_duplicates
        warnings << duplicates unless duplicates.empty?
        @metadata['dependencies'].each do |dep|
          e, w = metadata_dep_version_requirement(dep)
          errors << e unless e.nil?
          warnings << w unless w.nil?
          warnings << metadata_dep_version_range(dep['name']) if dep.key?('version_range')
        end
        [errors.flatten, warnings.flatten]
      end

      def metadata_deprecated_fields
        %w[types checksum].each_with_object([]) do |field, ary|
          next unless @metadata.key?(field)

          ary << metadata_err(:deprecated_fields, "Deprecated field '#{field}' found in metadata.json")
        end
      end

      def metadata_dep_duplicates
        results = []
        duplicates = @metadata['dependencies'].detect { |x| @metadata['dependencies'].count(x) > 1 }
        return results if duplicates.empty?

        duplicates.each { |x| results << metadata_err(:dependencies, "Duplicate dependencies on #{x}") }
        results
      end

      def metadata_dep_version_requirement(dependency)
        unless dependency.key?('version_requirement')
          return [metadata_err(:dependencies, "Invalid 'version_requirement' field in metadata.json: #{e}"), nil]
        end

        ver_req = MetadataJsonLint::VersionRequirement.new(dependency['version_requirement'])
        return [nil, metadata_dep_open_ended(dependency['name'], dependency['version_requirement'])] if ver_req.open_ended?
        return [nil, metadata_dep_mixed_syntax(dependency['name'], dependency['version_requirement'])] if ver_req.mixed_syntax?

        [nil, nil]
      end

      def metadata_dep_open_ended(name, version_req)
        metadata_err(:dependencies, "Dependency #{name} has an open ended dependency version requirement #{version_req}")
      end

      def metadata_dep_mixed_syntax(name, version_req)
        msg = 'Mixing "x" or "*" version syntax with operators is not recommended in ' \
              "metadata.json, use one style in the #{name} dependency: #{version_req}"
        metadata_err(:dependencies, msg)
      end

      def metadata_dep_version_range(name)
        metadata_err(:dependencies, "Dependency #{name} has a 'version_range' attribute which is no longer used by the forge.")
      end

      def metadata_err(check, msg)
        { check: check, msg: msg }
      end

      def linter_version
        PuppetLint::VERSION
      end

      def relative_manifests
        Dir.glob('manifests/**/*.pp')
      end

      def real_module_dir(path)
        return Pathname.pwd if path.nil?

        return Pathname.new(path).cleanpath(consider_symlink: true) if Dir.exist?(path)

        raise ArgumentError, "Path #{path} is not a directory"
      end
    end
  end
end
