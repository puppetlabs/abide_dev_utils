# frozen_string_literal: true

require 'json'
require 'shellwords'
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
          SPECIAL_CONTROL_IDS = %w[dependent cem_options cem_protected].freeze

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
                next if SPECIAL_CONTROL_IDS.include? control.id
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

        class ConfigExampleError < StandardError; end

        class ControlMarkdown
          def initialize(control, md, module_name, framework, formatter: nil)
            @control = control
            @md = md
            @module_name = module_name
            @framework = framework
            @formatter = formatter.nil? ? TypeExprValueFormatter : formatter
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
            if @framework == 'stig'
              @md.add_h2(@control.id)
            else
              @md.add_h2("#{@control.number} - #{@control.title}")
            end
          end

          def control_has_valid_params?
            return true if @control.params? || @control.resource.cem_options? || @control.resource.cem_protected?
            return true if @control.resource.manifest? && @control.resource.manifest.declaration.parameters?

            false
          end

          def resource_param(ctrl_param)
            return unless @control.resource.manifest?

            @control.resource.manifest.declaration.parameters&.find { |x| x.name == "$#{ctrl_param[:name]}" }
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

              val = @formatter.format(@control_data[param_hash[:name]][:default],
                                      @control_data[param_hash[:name]][:type_expr],
                                      optional_strategy: :placeholder)
              out_str << "#{indent}#{param_hash[:name]}: #{val}"
            end
            return if out_str.empty?

            @control.title.nil? ? out_str.unshift("    #{@control.id.dump}:") : out_str.unshift("    #{@control.title.dump}:")
            out_str.unshift('  control_configs:')
            out_str.unshift("#{@module_name}::config:")
            @md.add_ul('Hiera Configuration Example:')
            @md.add_code_block(out_str.join("\n"), language: 'yaml')
          rescue StandardError => e
            require 'pry'; binding.pry
            err_msg = [
              "Failed to generate config example for control #{@control.id}",
              "Error: #{e.message}",
              "Control: Data #{@control_data.inspect}",
              e.backtrace.join("\n")
            ].join("\n")
            raise ConfigExampleError, err_msg
          end

          def resource_reference_builder
            @md.add_ul("Resource: #{@md.code(@control.resource.to_reference)}")
          end
        end

        # Holds methods for formmating values based on type expressions
        class TypeExprValueFormatter
          UNDEF_VAL = 'undef'

          # Formats a value based on a type expression.
          # @param value [Any] the value to format
          # @param type_expr [String] the type expression to use for formatting
          # @param optional_strategy [Symbol] the strategy to use for optional values
          # @return [Any] the formatted value
          def self.format(value, type_expr, optional_strategy: :undef)
            return value if value == 'No parameters'

            case type_expr
            when /^(String|Stdlib::(Unix|Windows|Absolute)path|Enum)/
              quote(value)
            when /^Optional\[/
              optional(value, type_expr, strategy: optional_strategy)
            else
              return type_expr_placeholder(type_expr) if value.nil?

              quote(value)
            end
          end

          # Escapes and quotes a string. If value is not a string, returns value.
          # @param value [Any] the string to quote.
          # @return [String] the quoted string.
          # @return [Any] the value if it is not a string.
          def self.quote(value)
            if value.is_a?(String)
              value.inspect
            else
              value
            end
          end

          # Checks if a value is considered undef.
          # @param value [Any] the value to check.
          # @return [Boolean] true if value is considered undef (nil or 'undef').
          def self.undef?(value)
            value.nil? || value == UNDEF_VAL
          end

          # Returns the display representation of the value with an Optional type expression.
          # If the value is not nil or 'undef', returns the quoted form of the value.
          # @param value [Any] the value to format.
          # @param type_expr [String] the type expression.
          # @param strategy [Symbol] the strategy to use. Valid strategies are :undef and :placeholder.
          #   :undef will return 'undef' if the value is nil or 'undef'.
          #   :placeholder will return a peeled type expression placeholder if the value is nil or 'undef'.
          # @return [String] the formatted value.
          # @return [Any] the quoted value if it is not nil.
          def self.optional(value, type_expr, strategy: :undef)
            return UNDEF_VAL if undef?(value) && strategy == :undef
            return type_expr_placeholder(peel_type_expr(type_expr)) if undef?(value) && strategy == :placeholder

            quote(value)
          end

          # Returns a "peeled" type expression. Peeling a type expression removes the
          # first layer of the type expression. For example, if the type expression is
          # Optional[String], the peeled type expression is String.
          # @param type_expr [String] the type expression to peel.
          # @return [String] the peeled type expression.
          def self.peel_type_expr(type_expr)
            return type_expr unless type_expr.include?('[')

            type_expr.match(/^[A-Z][a-z0-9_]*\[(?<peeled>[A-Za-z0-9:,_{}=>\[\]\\\s]+)\]$/)[:peeled]
          end

          # Formats the type expression as a placeholder.
          # @param type_expr [String] The type expression to format.
          # @return [String] The formatted type expression.
          def self.type_expr_placeholder(type_expr)
            "<<Type #{type_expr}>>"
          end
        end
      end
    end
  end
end
