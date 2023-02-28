# frozen_string_literal: true

require 'set'
require_relative '../dot_number_comparable'
require_relative '../errors'
require_relative '../ppt'
require_relative 'mapping/mapper'

module AbideDevUtils
  module CEM
    # Represents a resource data resource statement
    class Resource
      attr_reader :title, :type

      def initialize(title, data, framework, mapper)
        @title = title
        @data = data
        @type = data['type']
        @framework = framework
        @mapper = mapper
        @dependent = []
      end

      # Returns a representation of the actual manifest backing this resource.
      # This is used to gather information from the Puppet code about this
      # resource.
      # @return [AbideDevUtils::Ppt::CodeIntrospection::Manifest]
      # @return [nil] if the manifest could not be found or could not be parsed
      def manifest
        @manifest ||= load_manifest
      end

      def manifest?
        !manifest.nil?
      end

      def file_path
        @file_path ||= AbideDevUtils::Ppt::ClassUtils.path_from_class_name((type == 'class' ? title : type))
      end

      def controls
        @controls || load_controls
      end

      def cem_options?
        !cem_options.empty?
      end

      def cem_options
        @cem_options ||= resource_properties('cem_options')
      end

      def cem_protected?
        !cem_protected.empty?
      end

      def cem_protected
        @cem_protected ||= resource_properties('cem_protected')
      end

      def dependent_controls
        @dependent_controls ||= @dependent.flatten.uniq.filter_map { |x| controls.find { |y| y.id == x } }
      end

      def to_reference
        "#{type.split('::').map(&:capitalize).join('::')}['#{title}']"
      end

      private

      attr_reader :data, :framework, :mapper

      def load_manifest
        AbideDevUtils::Ppt::CodeIntrospection::Manifest.new(file_path)
      rescue StandardError
        nil
      end

      def resource_properties(prop_name)
        props = Set.new
        return props unless data.key?(prop_name)

        data[prop_name].each do |param, param_val|
          props << { name: param,
                     type: ruby_class_to_puppet_type(param_val.class.to_s),
                     default: param_val }
        end
        props
      end

      def load_controls
        if data['controls'].respond_to?(:keys)
          load_hash_controls(data['controls'], framework, mapper)
        elsif data['controls'].respond_to?(:each_with_index)
          load_array_controls(data['controls'], framework, mapper)
        else
          raise "Control type is invalid. Type: #{data['controls'].class}"
        end
      end

      def load_hash_controls(ctrls, framework, mapper)
        ctrls.each_with_object([]) do |(name, data), arr|
          if name == 'dependent'
            @dependent << data
            next
          end
          ctrl = Control.new(name, data, self, framework, mapper)
          arr << ctrl
        rescue AbideDevUtils::Errors::ControlIdFrameworkMismatchError,
               AbideDevUtils::Errors::NoMappingDataForControlError
          next
        end
      end

      def load_array_controls(ctrls, framework, mapper)
        ctrls.each_with_object([]) do |c, arr|
          if c == 'dependent'
            @dependent << c
            next
          end
          ctrl = Control.new(c, 'no_params', self, framework, mapper)
          arr << ctrl
        rescue AbideDevUtils::Errors::ControlIdFrameworkMismatchError,
               AbideDevUtils::Errors::NoMappingDataForControlError
          next
        end
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
        when %r{Nilclass}
          'Optional'
        else
          pup_type
        end
      end
    end

    # Represents a singular rule in a benchmark
    class Control
      include AbideDevUtils::DotNumberComparable
      attr_reader :id, :params, :resource, :framework, :dependent

      def initialize(id, params, resource, framework, mapper)
        validate_id_with_framework(id, framework, mapper)
        @id = id
        @params = params
        @resource = resource
        @framework = framework
        @mapper = mapper
        raise AbideDevUtils::Errors::NoMappingDataForControlError, @id unless @mapper.get(id)
      end

      def params?
        !(params.nil? || params.empty? || params == 'no_params') || (resource.cem_options? || resource.cem_protected?)
      end

      def resource_properties?
        resource.cem_options? || resource.cem_protected?
      end

      def param_hashes
        return [no_params] unless params?

        params.each_with_object([]) do |(param, param_val), ar|
          ar << { name: param,
                  type: ruby_class_to_puppet_type(param_val.class.to_s),
                  default: param_val }
        end
      end

      def alternate_ids(level: nil, profile: nil)
        id_map = @mapper.get(id, level: level, profile: profile)
        if display_title_type.to_s == @mapper.map_type(id)
          id_map
        else
          alt_ids = id_map.each_with_object([]) do |mapval, arr|
            arr << if display_title_type.to_s == @mapper.map_type(mapval)
                     @mapper.get(mapval, level: level, profile: profile)
                   else
                     mapval
                   end
          end
          alt_ids.flatten.uniq
        end
      end

      def id_map_type
        @mapper.map_type(id)
      end

      def display_title
        send(display_title_type) unless display_title_type.nil?
      end

      def levels
        levels_and_profiles[0]
      end

      def profiles
        levels_and_profiles[1]
      end

      def valid_maps?
        valid = AbideDevUtils::CEM::Mapping::FRAMEWORK_TYPES[framework].each_with_object([]) do |mtype, arr|
          arr << if @mapper.map_type(id) == mtype
                   id
                 else
                   @mapper.get(id).find { |x| @mapper.map_type(x) == mtype }
                 end
        end
        valid.compact.length == AbideDevUtils::CEM::Mapping::FRAMEWORK_TYPES[framework].length
      end

      def method_missing(meth, *args, &block)
        meth_s = meth.to_s
        if AbideDevUtils::CEM::Mapping::ALL_TYPES.include?(meth_s)
          @mapper.get(id).find { |x| @mapper.map_type(x) == meth_s }
        else
          super
        end
      end

      def respond_to_missing?(meth, include_private = false)
        AbideDevUtils::CEM::Mapping::ALL_TYPES.include?(meth.to_s) || super
      end

      def to_h
        {
          id: id,
          display_title: display_title,
          alternate_ids: alternate_ids,
          levels: levels,
          profiles: profiles,
          params: param_hashes,
          resource: resource.to_stubbed_h,
        }
      end

      private

      def display_title_type
        if (!vulnid.nil? && !vulnid.is_a?(String)) || !title.is_a?(String)
          nil
        elsif framework == 'stig' && vulnid
          :vulnid
        else
          :title
        end
      end

      def validate_id_with_framework(id, framework, mapper)
        mtype = mapper.map_type(id)
        return if AbideDevUtils::CEM::Mapping::FRAMEWORK_TYPES[framework].include?(mtype)

        raise AbideDevUtils::Errors::ControlIdFrameworkMismatchError, [id, mtype, framework]
      end

      def map
        @map ||= @mapper.get(id)
      end

      def levels_and_profiles
        @levels_and_profiles ||= find_levels_and_profiles
      end

      def find_levels_and_profiles
        lvls = []
        profs = []
        @mapper.levels.each do |lvl|
          @mapper.profiles.each do |prof|
            unless @mapper.get(id, level: lvl, profile: prof).nil?
              lvls << lvl
              profs << prof
            end
          end
        end
        [lvls.flatten.compact.uniq, profs.flatten.compact.uniq]
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
        when %r{Nilclass}
          'Optional'
        else
          pup_type
        end
      end

      def no_params
        { name: 'No parameters', type: nil, default: nil }
      end
    end

    # Repesents a benchmark based on resource and mapping data
    class Benchmark
      attr_reader :osname, :major_version, :os_facts, :osfamily, :hiera_conf, :module_name, :framework

      def initialize(osname, major_version, hiera_conf, module_name, framework: 'cis')
        @osname = osname
        @major_version = major_version
        @os_facts = AbideDevUtils::Ppt::FacterUtils::FactSets.new.find_by_fact_value_tuples(['os.name', @osname],
                                                                                            ['os.release.major', @major_version])
        @osfamily = @os_facts['os']['family']
        @hiera_conf = hiera_conf
        @module_name = module_name
        @framework = framework
        @map_cache = {}
        @rules_in_map = {}
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
                benchmark = Benchmark.new(osname,
                                          v,
                                          pupmod.hiera_conf,
                                          pupmod.name(strip_namespace: true),
                                          framework: fw)
                benchmark.controls
                ary << benchmark
              rescue AbideDevUtils::Errors::MappingDataFrameworkMismatchError => e
                raise e unless ignore_all_errors || ignore_framework_mismatch
              rescue StandardError => e
                raise e unless ignore_all_errors
              end
            end
          else
            frameworks.each do |fw|
              benchmark = Benchmark.new(osname,
                                        majver,
                                        pupmod.hiera_conf,
                                        pupmod.name(strip_namespace: true),
                                        framework: fw)
              benchmark.controls
              ary << benchmark
            rescue AbideDevUtils::Errors::MappingDataFrameworkMismatchError => e
              raise e unless ignore_all_errors || ignore_framework_mismatch
            rescue StandardError => e
              raise e unless ignore_all_errors
            end
          end
        end
      end

      def resources
        @resources ||= resource_data["#{module_name}::resources"].each_with_object([]) do |(rtitle, rdata), arr|
          arr << Resource.new(rtitle, rdata, framework, mapper)
        end
      end

      def controls
        @controls ||= resources.map(&:controls).flatten.sort
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
      rescue StandardError => e
        require 'pry'; binding.pry
      end
    end
  end
end
