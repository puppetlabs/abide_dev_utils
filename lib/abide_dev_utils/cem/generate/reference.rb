# frozen_string_literal: true

require 'json'
require 'yaml'
require 'abide_dev_utils/markdown'
require 'abide_dev_utils/ppt'

module AbideDevUtils
  module CEM
    module Generate
      # Holds objects and methods for generating a reference doc
      module Reference
        MAPPING_PATH_KEY = 'Mapping Data'
        RESOURCE_DATA_PATH_KEY = 'Resource Data'

        def self.generate(data = {})
          pupmod = AbideDevUtils::Ppt::PuppetModule.new
          doc_title = case pupmod.name
                      when 'puppetlabs-cem_linux'
                        'CEM Linux Reference'
                      when 'puppetlabs-cem_windows'
                        'CEM Windows Reference'
                      else
                        'Reference'
                      end
          benchmarks = create_benchmark_objects(pupmod)
          case data.fetch(:format, 'markdown')
          when 'markdown'
            MarkdownGenerator.new(benchmarks).generate(doc_title)
          else
            raise "Format #{data[:format]} is unsupported! Only `markdown` format supported"
          end
        end

        def self.generate_markdown
          AbideDevUtils::Markdown.new('REFERENCE.md').generate
        end

        def self.create_benchmark_objects(pupmod)
          pupmod.supported_os.each_with_object([]) do |(osname, majver), ary|
            if majver.instance_of?(Array)
              majver.sort.each do |v|
                ary << Benchmark.new(osname, v, pupmod.hiera_conf, pupmod.name(strip_namespace: true))
              end
            else
              ary << Benchmark.new(osname, majver, pupmod.hiera_conf, pupmod.name(strip_namespace: true))
            end
          end
        end

        def self.config_example(control, params_array)
          out_str = ['cem_windows::config:', '  control_configs:', "    \"#{control}\":"]
          indent = '      '
          params_array.each do |param_hash|
            val = case param_hash[:type]
                  when 'String'
                    "'#{param_hash[:default]}'"
                  else
                    param_hash[:default]
                  end

            out_str << "#{indent}#{param_hash[:name]}: #{val}"
          end
          out_str.join("\n")
        end

        # Generates a markdown reference doc
        class MarkdownGenerator
          def initialize(benchmarks)
            @benchmarks = benchmarks
            @md = AbideDevUtils::Markdown.new('REFERENCE.md')
          end

          def generate(doc_title = 'Reference')
            md.add_title(doc_title)
            benchmarks.each do |benchmark|
              md.add_h1(benchmark.title_key)
              benchmark.rules.each do |title, rule|
                md.add_h2("#{rule['number']} #{title}")
                md.add_ul('Parameters:')
                rule['params'].each do |p|
                  md.add_ul("#{md.code(p[:name])} - [ #{md.code(p[:type])} ] - #{md.italic('Default:')} #{md.code(p[:default])}", indent: 1)
                end
                md.add_ul('Config Example:')
                example = config_example(benchmark.module_name, title, rule['params'])
                md.add_code_block(example, language: 'yaml')
                md.add_ul('Supported Levels:')
                rule['level'].each do |l|
                  md.add_ul(md.code(l), indent: 1)
                end
                md.add_ul('Supported Profiles:')
                rule['profile'].each do |l|
                  md.add_ul(md.code(l), indent: 1)
                end
                md.add_ul('Alternate Config IDs:')
                rule['alternate_ids'].each do |l|
                  md.add_ul(md.code(l), indent: 1)
                end
                md.add_ul("Resource: #{md.code(rule['resource'].capitalize)}")
              end
            end
            md.to_file
          end

          private

          attr_reader :benchmarks, :md

          def config_example(module_name, control, params_array)
            out_str = ["#{module_name}::config:", '  control_configs:', "    \"#{control}\":"]
            indent = '      '
            params_array.each do |param_hash|
              val = case param_hash[:type]
                    when 'String'
                      "'#{param_hash[:default]}'"
                    else
                      param_hash[:default]
                    end
              out_str << "#{indent}#{param_hash[:name]}: #{val}"
            end
            out_str.join("\n")
          end
        end

        # Repesents a benchmark for purposes of organizing data for markdown representation
        class Benchmark
          attr_reader :osname, :major_version, :hiera_conf, :module_name, :framework, :rules

          def initialize(osname, major_version, hiera_conf, module_name, framework: 'cis')
            @osname = osname
            @major_version = major_version
            @hiera_conf = hiera_conf
            @module_name = module_name
            @framework = framework
            @rules = {}
            @map_cache = {}
            load_rules
          end

          def map_data
            @map_data ||= load_mapping_data
          end

          def resource_data
            @resource_data ||= load_resource_data
          end

          def title
            return @title if defined?(@title)

            mtype = map_data.keys.first
            @title = map_data[mtype][map_top_key(mtype)]['benchmark']['title']
            @title
          end

          def version
            return @version if defined?(@version)

            mtype = map_data.keys.first
            @version = "v#{map_data[mtype][map_top_key(mtype)]['benchmark']['version']}"
            @version
          end

          def title_key
            return @title_key if defined?(@title_key)

            @title_key = "#{title} #{version}"
            @title_key
          end

          def add_rule(rule_hash)
            @rules << rule_hash
          end

          def map(control_id, level: nil, profile: nil)
            cache_key = [control_id, level, profile].compact.join('-')
            return @map_cache[cache_key] if @map_cache.key?(cache_key)

            mtype = map_type(control_id)
            mtop = map_top_key(mtype)
            unless level.nil? || profile.nil?
              @map_cache[cache_key] = map_data[mtype][mtop][level][profile][control_id]
              return @map_cache[cache_key]
            end
            map_data[mtype][mtop].each do |lvl, profile_hash|
              next if lvl == 'benchmark'

              profile_hash.each do |prof, control_hash|
                if control_hash.key?(control_id)
                  @map_cache[cache_key] = map_data[mtype][mtop][lvl][prof][control_id]
                  return @map_cache[cache_key]
                end
              end
            end
          end

          def map_type(control_id)
            case control_id
            when %r{^c[0-9_]+$}
              'hiera_title_num'
            when %r{^[0-9][0-9.]*$}
              'number'
            when %r{^[a-z][a-z0-9_]+$}
              'hiera_title'
            else
              'title'
            end
          end

          private

          def load_rules
            resource_data["#{module_name}::resources"].each do |_, rdata|
              unless rdata.key?('controls')
                puts "Controls key not found in #{rdata}"
                next
              end
              rdata['controls'].each do |control, control_data|
                rule_title = map(control).find { |id| map_type(id) == 'title' }
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
            control_data.each do |param, param_val|
              p_hashes << {
                name: param,
                type: ruby_class_to_puppet_type(param_val.class.to_s),
                default: param_val,
              }
            end
            p_hashes
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
            mtype = map_type(control_id)
            mtop = map_top_key(mtype)
            levels = []
            profiles = []
            map_data[mtype][mtop].each do |lvl, profile_hash|
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

          def map_top_key(mtype)
            [module_name, 'mappings', framework, mtype].join('::')
          end

          def load_mapping_data
            files = hiera_conf.local_hiera_files_with_fact('os.release.major', major_version, hierarchy_name: 'Mapping Data')
            files.each_with_object({}) do |f, h|
              next unless f.path.include?(framework)

              h[File.basename(f.path, '.yaml')] = YAML.load_file(f.path)
            end
          end

          def load_resource_data
            YAML.load_file(
              hiera_conf.local_hiera_files_with_facts(
                ['os.name', 'windows'],
                ['os.release.major', '10'],
                hierarchy_name: 'Resource Data'
              )[0].path
            )
          end
        end
      end
    end
  end
end
