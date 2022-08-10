# frozen_string_literal: true

require 'json'
require 'timeout'
require 'yaml'
require 'abide_dev_utils/markdown'
require 'abide_dev_utils/output'
require 'abide_dev_utils/ppt'
require 'abide_dev_utils/cem/benchmark'

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
          benchmarks = AbideDevUtils::CEM::Benchmark.benchmarks_from_puppet_module(pupmod)
          case data.fetch(:format, 'markdown')
          when 'markdown'
            file = data[:out_file] || 'REFERENCE.md'
            MarkdownGenerator.new(benchmarks, pupmod.name, file: file).generate(doc_title)
          else
            raise "Format #{data[:format]} is unsupported! Only `markdown` format supported"
          end
        end

        def self.generate_markdown
          AbideDevUtils::Markdown.new('REFERENCE.md').generate
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
          def initialize(benchmarks, module_name, file: 'REFERENCE.md')
            @benchmarks = benchmarks
            @module_name = module_name
            @file = file
            @md = AbideDevUtils::Markdown.new(@file)
          end

          def generate(doc_title = 'Reference')
            md.add_title(doc_title)
            benchmarks.each do |benchmark|
              progress_bar = AbideDevUtils::Output.progress(title: "Generating Markdown for #{benchmark.title_key}",
                                                            total: benchmark.controls.length)
              md.add_h1(benchmark.title_key)
              benchmark.controls.each do |control|
                next if ['cem_options', 'cem_protected', 'dependent'].include? control.id
                next if benchmark.framework == 'stig' && control.id_map_type != 'vulnid'

                control_md = ControlMarkdown.new(control, @md, @module_name, benchmark.framework)
                control_md.generate!
                progress_bar.increment
              rescue StandardError => e
                raise "Failed to generate markdown for control #{control.id}. Original message: #{e.message}"
              end
            end
            AbideDevUtils::Output.simple("Saving markdown to #{@file}")
            md.to_file
          end

          private

          attr_reader :benchmarks, :md
        end

        class ControlMarkdown
          def initialize(control, md, module_name, framework)
            @control = control
            @md = md
            @module_name = module_name
            @framework = framework
            @control_data = {}
          end

          def generate!
            heading_builder
            control_params_builder
            control_levels_builder
            control_profiles_builder
            config_example_builder
            control_alternate_ids_builder
            dependent_controls_builder
            resource_reference_builder
          end

          private

          def heading_builder
            @md.add_h2("#{@control.number} - #{@control.title}")
          end

          def control_has_valid_params?
            return true if @control.params? || @control.resource.cem_options? || @control.resource.cem_protected?
            return true if @control.resource.manifest? && @control.resource.manifest.declaration.parameters?

            false
          end

          def resource_param(ctrl_param)
            return unless @control.resource.manifest?

            @control.resource.manifest.declaration.parameters&.find { |x| x.name == "$#{ctrl_param[:name]}" }
            #raise "Cannot find resource parameter for param #{ctrl_param[:name]}" unless rparam
          end

          def param_type_expr(ctrl_param, rsrc_param)
            @control_data[ctrl_param[:name]] = {} unless @control_data.key?(ctrl_param[:name])
            @control_data[ctrl_param[:name]][:type_expr] = rsrc_param&.type_expr? ? rsrc_param&.type_expr : ctrl_param[:type]
            return unless @control_data[ctrl_param[:name]][:type_expr]

            " - [ #{@md.code(@control_data[ctrl_param[:name]][:type_expr])} ]"
          end

          def param_default_value(ctrl_param, rsrc_param)
            @control_data[ctrl_param[:name]] = {} unless @control_data.key?(ctrl_param[:name])
            @control_data[ctrl_param[:name]][:default] = ctrl_param[:default] || rsrc_param&.value
            return unless @control_data[ctrl_param[:name]][:default]

            " - #{@md.italic('Default:')} #{@md.code(@control_data[ctrl_param[:name]][:default])}"
          end

          def control_params_builder
            return unless control_has_valid_params?

            @md.add_ul('Parameters:')
            [@control.param_hashes, @control.resource.cem_options, @control.resource.cem_protected].each do |collection|
              collection.each do |hsh|
                rparam = resource_param(hsh)
                str_array = [@md.code(hsh[:name]), param_type_expr(hsh, rparam), param_default_value(hsh, rparam)]
                @md.add_ul(str_array.compact.join, indent: 1)
              end
            end
          end

          def control_levels_builder
            return unless @control.levels

            @md.add_ul('Supported Levels:')
            @control.levels.each do |l|
              @md.add_ul(@md.code(l), indent: 1)
            end
          end

          def control_profiles_builder
            return unless @control.profiles

            @md.add_ul('Supported Profiles:')
            @control.profiles.each do |l|
              @md.add_ul(@md.code(l), indent: 1)
            end
          end

          def control_alternate_ids_builder
            return if @framework == 'stig'

            @md.add_ul('Alternate Config IDs:')
            @control.alternate_ids.each do |l|
              @md.add_ul(@md.code(l), indent: 1)
            end
          end

          def dependent_controls_builder
            dep_ctrls = @control.resource.dependent_controls
            return if dep_ctrls.nil? || dep_ctrls.empty?

            @md.add_ul('Dependent controls:')
            dep_ctrls.each do |ctrl|
              puts "DEPENDENT: #{ctrl.id}"
              @md.add_ul(@md.code(ctrl.display_title), indent: 1)
            end
          end

          def config_example_builder
            out_str = []
            indent = '      '
            @control.param_hashes.each do |param_hash|
              next if param_hash[:name] == 'No parameters'

              val = if @control_data[param_hash[:name]][:default] &&
                       @control_data[param_hash[:name]][:type_expr]&.match?(/String|Path/)
                      "'#{@control_data[param_hash[:name]][:default]}'"
                    elsif @control_data[param_hash[:name]][:default]
                      @control_data[param_hash[:name]][:default]
                    elsif @control_data[param_hash[:name]][:type_expr]
                      "<#{@control_data[param_hash[:name]][:type_expr]}>"
                    else
                      'undef'
                    end
              out_str << "#{indent}#{param_hash[:name]}: #{val}"
            end
            return if out_str.empty?

            begin
              out_str.unshift("    #{@control.title.dump}:")
            rescue NoMethodError
              require 'pry'
              binding.pry
            end
            out_str.unshift('  control_configs:')
            out_str.unshift("#{@module_name}::config:")
            @md.add_ul('Hiera Configuration Example:')
            @md.add_code_block(out_str.join("\n"), language: 'yaml')
          end

          def resource_reference_builder
            @md.add_ul("Resource: #{@md.code(@control.resource.to_reference)}")
          end
        end
      end
    end
  end
end
