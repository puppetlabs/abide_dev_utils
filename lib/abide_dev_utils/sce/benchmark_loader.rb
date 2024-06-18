# frozen_string_literal: true

require_relative '../ppt/puppet_module'
require_relative 'benchmark'

module AbideDevUtils
  module Sce
    # Namespace for classes and methods for loading benchmarks
    module BenchmarkLoader
      # Load benchmarks from a Puppet module
      # @param module_dir [String] the directory of the Puppet module
      # @param opts [Hash] options for loading the benchmarks
      # @option opts [Boolean] :ignore_all_errors ignore all errors when loading benchmarks
      # @option opts [Boolean] :ignore_framework_mismatch ignore errors when the framework doesn't match
      # @return [Array<AbideDevUtils::Sce::Benchmark>] the loaded benchmarks
      def self.benchmarks_from_puppet_module(module_dir = Dir.pwd, **opts)
        PupMod.new(module_dir, **opts).load
      end

      # Loads benchmark data for a Puppet module
      class PupMod
        attr_reader :pupmod, :load_errors, :load_warnings, :ignore_all_errors, :ignore_framework_mismatch

        def initialize(module_dir = Dir.pwd, **opts)
          @pupmod = AbideDevUtils::Ppt::PuppetModule.new(module_dir)
          @load_errors = []
          @load_warnings = []
          @ignore_all_errors = opts.fetch(:ignore_all_errors, false)
          @ignore_framework_mismatch = opts.fetch(:ignore_framework_mismatch, false)
        end

        # Load the benchmark from the Puppet module
        # @return [Array<AbideDevUtils::Sce::Benchmark>] the loaded benchmarks
        # @raise [AbideDevUtils::Errors::BenchmarkLoadError] if a benchmark fails to load
        def load
          clear_load_errors
          clear_load_warnings
          pupmod.supported_os.each_with_object([]) do |supp_os, ary|
            osname, majver = supp_os.split('::')
            if majver.is_a?(Array)
              majver.sort.each do |v|
                frameworks.each do |fw|
                  ary << new_benchmark(osname, v, fw)
                rescue StandardError => e
                  handle_load_error(e, fw, osname, v, pupmod.name(strip_namespace: true))
                end
              end
            else
              frameworks.each do |fw|
                ary << new_benchmark(osname, majver, fw)
              rescue StandardError => e
                handle_load_error(e, fw, osname, majver, pupmod.name(strip_namespace: true))
              end
            end
          end
        end

        private

        def clear_load_errors
          @load_errors = []
        end

        def clear_load_warnings
          @load_warnings = []
        end

        def frameworks
          @frameworks ||= pupmod.hiera_conf.local_hiera_files(hierarchy_name: 'Mapping Data').each_with_object([]) do |hf, ary|
            parts = hf.path.split(pupmod.hiera_conf.default_datadir)[-1].split('/')
            ary << parts[2] unless ary.include?(parts[2])
          end
        end

        def new_benchmark(osname, majver, framework)
          benchmark = AbideDevUtils::Sce::Benchmark.new(
            osname,
            majver,
            pupmod.hiera_conf,
            pupmod.name(strip_namespace: true),
            framework: framework
          )
          benchmark.controls
          benchmark
        end

        def handle_load_error(error, framework, osname, majver, module_name)
          err = AbideDevUtils::Errors::BenchmarkLoadError.new(error.message)
          err.set_backtrace(error.backtrace)
          err.framework = framework
          err.osname = osname
          err.major_version = majver
          err.module_name = module_name
          err.original_error = error
          if error.is_a?(AbideDevUtils::Errors::MappingDataFrameworkMismatchError) && ignore_framework_mismatch
            @load_warnings << err
          elsif ignore_all_errors
            @load_errors << err
          else
            @load_errors << err
            raise err
          end
        end
      end
    end
  end
end
