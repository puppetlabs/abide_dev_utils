# frozen_string_literal: true

require 'date'
require 'json'
require 'pathname'
require 'yaml'
require_relative '../../ppt'
require_relative '../../validate'
require_relative '../benchmark_loader'

module AbideDevUtils
  module Sce
    module Generate
      # Methods and objects used to construct a report of what SCE enforces versus what
      # the various compliance frameworks expect to be enforced.
      module CoverageReport
        # Generate a coverage report for a Puppet module
        # @param format_func [Symbol] the format function to use
        # @param opts [Hash] options for generating the report
        # @option opts [String] :benchmark the benchmark to generate the report for
        # @option opts [String] :profile the profile to generate the report for
        # @option opts [String] :level the level to generate the report for
        # @option opts [Symbol] :format_func the format function to use
        # @option opts [Boolean] :ignore_benchmark_errors ignore all errors when loading benchmarks
        # @option opts [String] :xccdf_dir the directory containing the XCCDF files
        def self.generate(format_func: :to_h, opts: {})
          opts = ReportOptions.new(opts)
          benchmarks = AbideDevUtils::Sce::BenchmarkLoader.benchmarks_from_puppet_module(
            ignore_all_errors: opts.ignore_benchmark_errors
          )
          benchmarks.filter_map do |b|
            next if opts.benchmark && !Regexp.new(Regexp.escape(opts.benchmark)).match?(b.title_key)
            next if opts.profile && b.mapper.profiles.none?(opts.profile)
            next if opts.level && b.mapper.levels.none?(opts.level)

            BenchmarkReport.new(b, opts).run.send(format_func)
          end
        end

        # Holds options for generating a report
        class ReportOptions
          DEFAULTS = {
            benchmark: nil,
            profile: nil,
            level: nil,
            format_func: :to_h,
            ignore_benchmark_errors: false,
            xccdf_dir: nil
          }.freeze

          attr_reader(*DEFAULTS.keys)

          def initialize(opts = {})
            @opts = DEFAULTS.merge(opts)
            DEFAULTS.each_key do |k|
              instance_variable_set "@#{k}", @opts[k]
            end
          end

          def report_type
            @report_type ||= (xccdf_dir.nil? ? :basic_coverage : :correlated_coverage)
          end
        end

        class Filter
          KEY_FACT_MAP = {
            os_family: 'os.family',
            os_name: 'os.name',
            os_release_major: 'os.release.major'
          }.freeze

          attr_reader(*KEY_FACT_MAP.keys)

          def initialize(pupmod, **filters)
            @pupmod = pupmod
            @benchmark = filters[:benchmark]
            @profile = filters[:profile]
            @level = filters[:level]
            KEY_FACT_MAP.each_key do |k|
              instance_variable_set "@#{k}", filters[k]
            end
          end

          def resource_data
            @resource_data ||= find_resource_data
          end

          def mapping_data
            @mapping_data ||= find_mapping_data
          end

          private

          def find_resource_data
            fact_array = fact_array_for(:os_family, :os_name, :os_release_major)
            @pupmod.hiera_conf.local_hiera_files_with_facts(*fact_array, hierarchy_name: 'Resource Data').map do |f|
              YAML.load_file(f.path)
            end
          rescue NoMethodError
            @pupmod.hiera_conf.local_hiera_files(hierarchy_name: 'Resource Data').map { |f| YAML.load_file(f.path) }
          end

          def find_mapping_data
            fact_array = fact_array_for(:os_name, :os_release_major)
            begin
              data_array = @pupmod.hiera_conf.local_hiera_files_with_facts(*fact_array,
                                                                           hierarchy_name: 'Mapping Data').map do |f|
                YAML.load_file(f.path)
              end
            rescue NoMethodError
              data_array = @pupmod.hiera_conf.local_hiera_files(hierarchy_name: 'Mapping Data').map do |f|
                YAML.load_file(f.path)
              end
            end
            filter_mapping_data_array_by_benchmark!(data_array)
            filter_mapping_data_array_by_profile!(data_array)
            filter_mapping_data_array_by_level!(data_array)
            data_array
          end

          def filter_mapping_data_array_by_benchmark!(data_array)
            return unless @benchmark

            data_array.select! do |d|
              d.keys.all? do |k|
                k == 'benchmark' || k.match?(/::#{@benchmark}::/)
              end
            end
          end

          def filter_mapping_data_array_by_profile!(data_array)
            return unless @profile

            data_array.reject! { |d| nested_hash_value(d, @profile).nil? }
          end

          def filter_mapping_data_array_by_level!(data_array)
            return unless @level

            data_array.reject! { |d| nested_hash_value(d, @level).nil? }
          end

          def nested_hash_value(obj, key)
            if obj.respond_to?(:key?) && obj.key?(key)
              obj[key]
            elsif obj.respond_to?(:each)
              r = nil
              obj.find { |*a| r = nested_hash_value(a.last, key) }
              r
            end
          end

          def filter_stig_mapping_data(data_array); end

          def fact_array_for(*keys)
            keys.each_with_object([]) { |(k, _), a| a << fact_filter_value(k) }.compact
          end

          def fact_filter_value(key)
            value = instance_variable_get("@#{key}")
            return if value.nil? || value.empty?

            [KEY_FACT_MAP[key], value]
          end
        end

        # Class manages organizing report data into various output formats
        class ReportOutput
          attr_reader :controls_in_resource_data, :rules_in_map, :timestamp,
                      :title

          def initialize(benchmark, controls_in_resource_data, rules_in_map, profile: nil, level: nil)
            @benchmark = benchmark
            @controls_in_resource_data = controls_in_resource_data
            @rules_in_map = rules_in_map
            @profile = profile
            @level = level
            @timestamp = DateTime.now.iso8601
            @title = "Coverage Report for #{@benchmark.title_key}"
          end

          def uncovered
            @uncovered ||= rules_in_map - controls_in_resource_data
          end

          def uncovered_count
            @uncovered_count ||= uncovered.length
          end

          def covered
            @covered ||= rules_in_map - uncovered
          end

          def covered_count
            @covered_count ||= covered.length
          end

          def total_count
            @total_count ||= rules_in_map.length
          end

          def percentage
            @percentage ||= covered_count.to_f / total_count
          end

          def to_h
            {
              title: title,
              timestamp: timestamp,
              benchmark: benchmark_hash,
              coverage: coverage_hash
            }
          end

          def to_json(opts = nil)
            JSON.generate(to_h, opts)
          end

          def to_yaml
            to_h.to_yaml
          end

          def benchmark_hash
            {
              title: @benchmark.title,
              version: @benchmark.version,
              framework: @benchmark.framework,
              profile: @profile || 'all',
              level: @level || 'all'
            }
          end

          def coverage_hash
            {
              total_count: total_count,
              uncovered_count: uncovered_count,
              uncovered: uncovered,
              covered_count: covered_count,
              covered: covered,
              percentage: percentage,
              controls_in_resource_data: controls_in_resource_data,
              rules_in_map: rules_in_map
            }
          end
        end

        # Creates ReportOutput objects based on the given Benchmark
        class BenchmarkReport
          def initialize(benchmark, opts = ReportOptions.new)
            @benchmark = benchmark
            @opts = opts
            @special_control_names = %w[sce_options sce_protected]
            @stig_map_types = %w[vulnid ruleid]
          end

          def run
            send(@opts.report_type)
          end

          def controls_in_resource_data
            @controls_in_resource_data ||= find_controls_in_resource_data
          end

          def controls_in_mapping_data
            @controls_in_mapping_data ||= find_controls_in_mapping_data
          end

          def basic_coverage(level: @opts.level, profile: @opts.profile)
            map_type = @benchmark.map_type(controls_in_resource_data[0])
            rules_in_map = @benchmark.rules_in_map(map_type, level: level, profile: profile)
            ReportOutput.new(@benchmark, controls_in_resource_data, rules_in_map, profile: profile, level: level)
          end

          # def correlated_coverage(level: @opts.level, profile: @opts.profile)
          #   correlation = ReportOutputCorrelation.new(basic_coverage(level: level, profile: profile))
          # end

          private

          def find_controls_in_resource_data
            controls = @benchmark.resource_data["#{@benchmark.module_name}::resources"].each_with_object([]) do |(_rname, rval), arr|
              arr << case rval['controls'].class.to_s
                     when 'Hash'
                       rval['controls'].keys
                     when 'Array'
                       rval['controls']
                     else
                       raise "Invalid controls type: #{rval['controls'].class}"
                     end
            end
            controls.flatten.uniq.select do |c|
              if @special_control_names.include? c
                false
              else
                case @benchmark.framework
                when 'cis'
                  @stig_map_types.none? @benchmark.map_type(c)
                when 'stig'
                  @stig_map_types.include? @benchmark.map_type(c)
                else
                  raise "Cannot find controls for framework #{@benchmark.framework}"
                end
              end
            end
          end

          def find_controls_in_mapping_data
            controls = @benchmark.map_data[0].each_with_object([]) do |(_, mapping), arr|
              mapping.each do |level, profs|
                next if level == 'benchmark'

                case @benchmark.framework
                when 'cis'
                  profs.each do |_, ctrls|
                    arr << ctrls.keys
                    arr << ctrls.values
                  end
                when 'stig'
                  require 'pry'
                  binding.pry
                else
                  raise "Cannot find controls for framework #{@benchmark.framework}"
                end
              end
            end
            controls.flatten.uniq
          end
        end

        class ReportOutputCorrelation
          def initialize(cov_rep)
            @cov_rep = cov_rep
          end
        end
      end
    end
  end
end
