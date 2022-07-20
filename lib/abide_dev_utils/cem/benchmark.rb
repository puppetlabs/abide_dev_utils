# frozen_string_literal: true

require 'abide_dev_utils/errors'
require 'abide_dev_utils/ppt/facter_utils'
require 'abide_dev_utils/cem/mapping/mapper'

module AbideDevUtils
  module CEM
    # Repesents a benchmark for purposes of organizing data for markdown representation
    class Benchmark
      attr_reader :osname, :major_version, :os_facts, :osfamily, :hiera_conf, :module_name, :framework, :rules

      def initialize(osname, major_version, hiera_conf, module_name, framework: 'cis')
        @osname = osname
        @major_version = major_version
        @os_facts = AbideDevUtils::Ppt::FacterUtils.recursive_facts_for_os(@osname, @major_version)
        @osfamily = @os_facts['os']['family']
        @hiera_conf = hiera_conf
        @module_name = module_name
        @framework = framework
        @rules = {}
        @map_cache = {}
        @rules_in_map = {}
        load_rules
      end

      # Creates Benchmark objects from a Puppet module
      # @param pupmod [AbideDevUtils::Ppt::PuppetModule] A PuppetModule instance
      # @param skip_errors [Boolean] True skips errors and loads non-erroring benchmarks, false raises the error.
      # @return [Array<AbideDevUtils::CEM::Benchmark>] Array of Benchmark instances
      def self.benchmarks_from_puppet_module(pupmod, ignore_all_errors: false, ignore_framework_mismatch: true)
        frameworks = pupmod.hiera_conf.local_hiera_files(hierarchy_name: 'Mapping Data').each_with_object([]) do |hf, ary|
          parts = hf.path.split(pupmod.hiera_conf.default_datadir)[-1].split('/')
          ary << parts[2] unless ary.include?(parts[2])
        end
        pupmod.supported_os.each_with_object([]) do |supp_os, ary|
          osname, majver = supp_os.split('::')
          if majver.is_a?(Array)
            majver.sort.each do |v|
              frameworks.each do |fw|
                benchmark = Benchmark.new(osname, v, pupmod.hiera_conf, pupmod.name(strip_namespace: true), framework: fw)
                ary << benchmark
              rescue StandardError => e
                raise e unless ignore_all_errors || (e.instance_of?(AbideDevUtils::Errors::MappingDataFrameworkMismatchError) && ignore_framework_mismatch)
              end
            end
          else
            frameworks.each do |fw|
              benchmark = Benchmark.new(osname, majver, pupmod.hiera_conf, pupmod.name(strip_namespace: true), framework: fw)
              ary << benchmark
            rescue StandardError => e
              raise e unless ignore_all_errors || (e.instance_of?(AbideDevUtils::Errors::MappingDataFrameworkMismatchError) && ignore_framework_mismatch)
            end
          end
        end
      end

      def mapper
        @mapper ||= AbideDevUtils::CEM::Mapping::Mapper.new(module_name, framework, load_mapping_data)
      end

      def map_data
        mapper.map_data
      end

      def resource_data
        @resource_data ||= load_resource_data
      end

      def title
        mapper.title
      end

      def version
        mapper.version
      end

      def title_key
        @title_key ||= "#{title} #{version}"
      end

      def add_rule(rule_hash)
        @rules << rule_hash
      end

      def rules_in_map(mtype, level: nil, profile: nil)
        real_mtype = map_type(mtype)
        cache_key = [real_mtype, level, profile].compact.join('-')
        return @rules_in_map[cache_key] if @rules_in_map.key?(cache_key)

        all_rim = mapper.each_with_array_like(real_mtype) do |(lvl, profs), arr|
          next if lvl == 'benchmark' || (!level.nil? && lvl != level)

          profs.each do |prof, maps|
            next if !profile.nil? && prof != profile

            # CIS and STIG differ in that STIG does not have profiles
            control_ids = maps.respond_to?(:keys) ? maps.keys : prof
            arr << control_ids
          end
        end
        @rules_in_map[cache_key] = all_rim.flatten.uniq
        @rules_in_map[cache_key]
      end

      def map(control_id, level: nil, profile: nil)
        mapper.get(control_id, level: level, profile: profile)
      end

      def map_type(control_id)
        mapper.map_type(control_id)
      end

      private

      def load_rules
        resource_data["#{module_name}::resources"].each do |_, rdata|
          unless rdata.key?('controls')
            puts "Controls key not found in #{rdata}"
            next
          end
          rdata['controls'].each do |control, control_data|
            rule_title = map(control)
            next if rule_title.nil? || rule_title.empty?

            rule_title.find { |id| map_type(id) == 'title' }
            alternate_ids = map(rule_title)

            next unless rule_title.is_a?(String)

            @rules[rule_title] = {} unless @rules&.key?(rule_title)
            @rules[rule_title]['number'] = alternate_ids.find { |id| map_type(id) == 'number' }
            @rules[rule_title]['alternate_ids'] = alternate_ids
            @rules[rule_title]['params'] = [] unless @rules[rule_title].key?('params')
            @rules[rule_title]['level'] = [] unless @rules[rule_title].key?('level')
            @rules[rule_title]['profile'] = [] unless @rules[rule_title].key?('profile')
            param_hashes(control_data).each do |param_hash|
              next if @rules[rule_title]['params'].include?(param_hash[:name])

              @rules[rule_title]['params'] << param_hash
            end
            levels, profiles = find_levels_and_profiles(control)
            unless @rules[rule_title]['level'] == levels
              @rules[rule_title]['level'] = @rules[rule_title]['level'] | levels
            end
            unless @rules[rule_title]['profile'] == profiles
              @rules[rule_title]['profile'] = @rules[rule_title]['profile'] | profiles
            end
            @rules[rule_title]['resource'] = rdata['type']
          end
        end
        @rules = sort_rules
      end

      def param_hashes(control_data)
        return [] if control_data.nil? || control_data.empty?

        p_hashes = []
        if !control_data.respond_to?(:each) && control_data == 'no_params'
          p_hashes << no_params
        else
          control_data.each do |param, param_val|
            p_hashes << {
              name: param,
              type: ruby_class_to_puppet_type(param_val.class.to_s),
              default: param_val,
            }
          end
        end
        p_hashes
      end

      def no_params
        { name: 'No parameters', type: nil, default: nil }
      end

      # We sort the rules by their control number so they
      # appear in the REFERENCE in benchmark order
      def sort_rules
        sorted = @rules.dup.sort_by do |_, v|
          control_num_to_int(v['number'])
        end
        sorted.to_h
      end

      # In order to sort the rules by their control number,
      # we need to convert the control number to an integer.
      # This is a rough conversion, but should be sufficient
      # for the purposes of sorting. The multipliers are
      # the 20th, 15th, 10th, and 5th numbers in the Fibonacci
      # sequence, then 1 after that. The reason for this is to
      # ensure a "spiraled" wieghting of the sections in the control
      # number, with 1st section having the most sorting weight, 2nd
      # having second most, etc. However, the differences in the multipliers
      # are such that it would be difficult for the product of a lesser-weighted
      # section to be greater than a greater-weighted section.
      def control_num_to_int(control_num)
        multipliers = [6765, 610, 55, 5, 1]
        nsum = 0
        midx = 0
        control_num.split('.').each do |num|
          multiplier = midx >= multipliers.length ? 1 : multipliers[midx]
          nsum += num.to_i * multiplier
          midx += 1
        end
        nsum
      end

      def find_levels_and_profiles(control_id)
        levels = []
        profiles = []
        mapper.each_like(control_id) do |lvl, profile_hash|
          next if lvl == 'benchmark'

          profile_hash.each do |prof, _|
            unless map(control_id, level: lvl, profile: prof).nil?
              levels << lvl
              profiles << prof
            end
          end
        end
        [levels, profiles]
      end

      def ruby_class_to_puppet_type(class_name)
        pup_type = class_name.split('::').last.capitalize
        case pup_type
        when %r{(Trueclass|Falseclass)}
          'Boolean'
        when %r{(String|Pathname)}
          'String'
        when %r{(Integer|Fixnum)}
          'Integer'
        when %r{(Float|Double)}
          'Float'
        else
          pup_type
        end
      end

      def load_mapping_data
        files = case module_name
                when /_windows$/
                  cem_windows_mapping_files
                when /_linux$/
                  cem_linux_mapping_files
                else
                  raise "Module name '#{module_name}' is not a CEM module"
                end
        validate_mapping_files_framework(files).each_with_object({}) do |f, h|
          next unless f.path.include?(framework)

          h[File.basename(f.path, '.yaml')] = YAML.load_file(f.path)
        end
      end

      def cem_linux_mapping_files
        facts = [['os.name', osname], ['os.release.major', major_version]]
        mapping_files = hiera_conf.local_hiera_files_with_facts(*facts, hierarchy_name: 'Mapping Data')
        raise AbideDevUtils::Errors::MappingFilesNotFoundError, facts if mapping_files.nil? || mapping_files.empty?

        mapping_files
      end

      def cem_windows_mapping_files
        facts = ['os.release.major', major_version]
        mapping_files = hiera_conf.local_hiera_files_with_fact(facts[0], facts[1], hierarchy_name: 'Mapping Data')
        raise AbideDevUtils::Errors::MappingFilesNotFoundError, facts if mapping_files.nil? || mapping_files.empty?

        mapping_files
      end

      def validate_mapping_files_framework(files)
        validated_files = files.select { |f| f.path_parts.include?(framework) }
        if validated_files.nil? || validated_files.empty?
          raise AbideDevUtils::Errors::MappingDataFrameworkMismatchError, framework
        end

        validated_files
      end

      def load_resource_data
        facts = [['os.family', osfamily], ['os.name', osname], ['os.release.major', major_version]]
        rdata_files = hiera_conf.local_hiera_files_with_facts(*facts, hierarchy_name: 'Resource Data')
        raise AbideDevUtils::Errors::ResourceDataNotFoundError, facts if rdata_files.nil? || rdata_files.empty?

        YAML.load_file(rdata_files[0].path)
      end
    end
  end
end
