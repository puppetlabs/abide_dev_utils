# frozen_string_literal: true

require 'date'
require 'json'
require 'pathname'
require 'yaml'
require 'abide_dev_utils/ppt'
require 'abide_dev_utils/validate'
require 'abide_dev_utils/cem/benchmark'

module AbideDevUtils
  module CEM
    # Methods and objects used to construct a report of what CEM enforces versus what
    # the various compliance frameworks expect to be enforced.
    module CoverageReport
      # def self.generate(outfile: 'cem_coverage.yaml', **_filters)
      #   pupmod = AbideDevUtils::Ppt::PuppetModule.new
      #   # filter = Filter.new(pupmod, **filters)
      #   benchmarks = AbideDevUtils::CEM::Benchmark.benchmarks_from_puppet_module(pupmod)
      #   Report.new(benchmarks).generate(outfile: outfile)
      # end

      def self.basic_coverage(format_func: :to_yaml, ignore_benchmark_errors: false)
        pupmod = AbideDevUtils::Ppt::PuppetModule.new
        # filter = Filter.new(pupmod, **filters)
        benchmarks = AbideDevUtils::CEM::Benchmark.benchmarks_from_puppet_module(pupmod,
                                                                                 ignore_all_errors: ignore_benchmark_errors)
        benchmarks.map do |b|
          AbideDevUtils::CEM::CoverageReport::BenchmarkReport.new(b).basic_coverage.send(format_func)
        end
      end

      class Filter
        KEY_FACT_MAP = {
          os_family: 'os.family',
          os_name: 'os.name',
          os_release_major: 'os.release.major',
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
            data_array = @pupmod.hiera_conf.local_hiera_files_with_facts(*fact_array, hierarchy_name: 'Mapping Data').map do |f|
              YAML.load_file(f.path)
            end
          rescue NoMethodError
            data_array = @pupmod.hiera_conf.local_hiera_files(hierarchy_name: 'Mapping Data').map { |f| YAML.load_file(f.path) }
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

      class OldReport
        def initialize(benchmarks)
          @benchmarks = benchmarks
        end

        def self.generate
          coverage = {}
          coverage['classes'] = {}
          all_cap = ClassUtils.find_all_classes_and_paths(puppet_class_dir)
          invalid_classes = find_invalid_classes(all_cap)
          valid_classes = find_valid_classes(all_cap, invalid_classes)
          coverage['classes']['invalid'] = invalid_classes
          coverage['classes']['valid'] = valid_classes
          hiera = YAML.safe_load(File.open(hiera_path))
          profile&.gsub!(/^profile_/, '') unless profile.nil?

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

        def self.find_valid_classes(all_cap, invalid_classes)
          all_classes = all_cap.dup.transpose[0]
          return [] if all_classes.nil?

          return all_classes - invalid_classes unless invalid_classes.nil?

          all_classes
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

      # Class manages organizing report data into various output formats
      class ReportOutput
        attr_reader :controls_in_resource_data, :rules_in_map, :timestamp,
                    :title

        def initialize(benchmark, controls_in_resource_data, rules_in_map)
          @benchmark = benchmark
          @controls_in_resource_data = controls_in_resource_data
          @rules_in_map = rules_in_map
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
            coverage: coverage_hash,
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
            rules_in_map: rules_in_map,
          }
        end
      end

      # Creates ReportOutput objects based on the given Benchmark
      class BenchmarkReport
        def initialize(benchmark)
          @benchmark = benchmark
        end

        def controls_in_resource_data
          @controls_in_resource_data ||= find_controls_in_resource_data
        end

        def controls_in_mapping_data
          @controls_in_mapping_data ||= find_controls_in_mapping_data
        end

        def basic_coverage(level: nil, profile: nil)
          map_type = @benchmark.map_type(controls_in_resource_data[0])
          rules_in_map = @benchmark.rules_in_map(map_type, level: level, profile: profile)
          AbideDevUtils::CEM::CoverageReport::ReportOutput.new(@benchmark, controls_in_resource_data, rules_in_map)
        end

        private

        def find_controls_in_resource_data
          controls = @benchmark.resource_data["#{@benchmark.module_name}::resources"].each_with_object([]) do |(rname, rval), arr|
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
            case @benchmark.framework
            when 'cis'
              @benchmark.map_type(c) != 'vulnid'
            when 'stig'
              @benchmark.map_type(c) == 'vulnid'
            else
              raise "Cannot find controls for framework #{@benchmark.framework}"
            end
          end
        end

        def find_controls_in_mapping_data
          controls = @benchmark.map_data[0].each_with_object([]) do |(_, mapping), arr|
            mapping.each do |level, profs|
              next if level == 'benchmark'

              profs.each do |_, ctrls|
                arr << ctrls.keys
                arr << ctrls.values
              end
            end
          end
          controls.flatten.uniq
        end
      end
    end
  end
end
