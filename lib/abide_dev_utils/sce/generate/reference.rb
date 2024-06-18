# frozen_string_literal: true

require 'json'
require 'puppet-strings'
require 'puppet-strings/yard'
require 'shellwords'
require 'timeout'
require 'yaml'
require_relative '../../markdown'
require_relative '../../output'
require_relative '../../ppt'
require_relative '../benchmark_loader'

module AbideDevUtils
  module Sce
    module Generate
      # Holds objects and methods for generating a reference doc
      module Reference
        MAPPING_PATH_KEY = 'Mapping Data'
        RESOURCE_DATA_PATH_KEY = 'Resource Data'

        # @return [Array<Array<StandardError>>] Returns a 2d array with two items. The first item
        #   is an array containing StandardError-derived objects that are considered halting errors
        #   in reference generation. The second item is an array of StandardError-derived objects
        #   that are considered non-halting (warning) errors.
        def self.generate(data = {})
          pupmod_path = data[:module_dir] || Dir.pwd
          bm_loader = BenchmarkLoader::PupMod.new(pupmod_path, ignore_framework_mismatch: true)
          doc_title = case bm_loader.pupmod.name
                      when 'puppetlabs-sce_linux'
                        'SCE for Linux Reference'
                      when 'puppetlabs-sce_windows'
                        'SCE for Windows Reference'
                      else
                        'Reference'
                      end
          benchmarks = bm_loader.load
          case data.fetch(:format, 'markdown')
          when 'markdown'
            file = data[:out_file] || 'REFERENCE.md'
            MarkdownGenerator.new(benchmarks, bm_loader.pupmod.name, file: file, opts: data).generate(doc_title)
          else
            raise "Format #{data[:format]} is unsupported! Only `markdown` format supported"
          end
          [bm_loader.load_errors, bm_loader.load_warnings]
        end

        def self.generate_markdown
          AbideDevUtils::Markdown.new('REFERENCE.md').generate
        end

        def self.config_example(control, params_array)
          out_str = ['sce_windows::config:', '  control_configs:', "    \"#{control}\":"]
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
          SPECIAL_CONTROL_IDS = %w[dependent sce_options sce_protected].freeze

          def initialize(benchmarks, module_name, file: 'REFERENCE.md', opts: {})
            @benchmarks = benchmarks
            @module_name = module_name
            @file = file
            @opts = opts
            @md = AbideDevUtils::Markdown.new(@file)
          end

          def generate(doc_title = 'Reference')
            @strings = Strings.new(opts: @opts)
            md.add_title(doc_title)
            benchmarks.each do |benchmark|
              unless @opts[:quiet]
                progress_bar = AbideDevUtils::Output.progress(title: "Generating Markdown for #{benchmark.title_key}",
                                                              total: benchmark.controls.length)
              end
              md.add_h1(benchmark.title_key)
              benchmark.controls.each do |control|
                next if SPECIAL_CONTROL_IDS.include? control.id
                next if benchmark.framework == 'stig' && control.id_map_type != 'vulnid'

                control_md = ControlMarkdown.new(control, @md, @strings, @module_name, benchmark.framework, opts: @opts)
                control_md.generate! if control_md.verify_profile_and_level_selections
                progress_bar.increment unless @opts[:quiet]
              rescue StandardError => e
                raise "Failed to generate markdown for control #{control.id}. Original message: #{e.message}"
              end
            end
            AbideDevUtils::Output.simple("Saving markdown to #{@file}") unless @opts[:quiet]
            md.to_file
          end

          private

          attr_reader :benchmarks, :md
        end

        class ConfigExampleError < StandardError; end

        # Puppet Strings reference object
        class Strings
          REGISTRY_TYPES = %i[
            root
            module
            class
            puppet_class
            puppet_data_type
            puppet_data_type_alias
            puppet_defined_type
            puppet_type
            puppet_provider
            puppet_function
            puppet_task
            puppet_plan
          ].freeze

          attr_reader :search_patterns

          def initialize(search_patterns: nil, opts: {})
            @search_patterns = search_patterns || PuppetStrings::DEFAULT_SEARCH_PATTERNS
            @debug = opts[:debug]
            @quiet = opts[:quiet]
            PuppetStrings::Yard.setup!
            YARD::CLI::Yardoc.run(*yard_args(@search_patterns, debug: @debug, quiet: @quiet))
          end

          def debug?
            !!@debug
          end

          def quiet?
            !!@quiet
          end

          def registry
            @registry ||= YARD::Registry.all(*REGISTRY_TYPES)
          end

          def find_resource(resource_name)
            to_h.each do |_, resources|
              res = resources.find { |r| r[:name] == resource_name.to_sym }
              return res if res
            end
          end

          def puppet_classes
            @puppet_classes ||= hashes_for_reg_type(:puppet_class)
          end

          def data_types
            @data_types ||= hashes_for_reg_type(:puppet_data_types)
          end

          def data_type_aliases
            @data_type_aliases ||= hashes_for_reg_type(:puppet_data_type_alias)
          end

          def defined_types
            @defined_types ||= hashes_for_reg_type(:puppet_defined_type)
          end

          def resource_types
            @resource_types ||= hashes_for_reg_type(:puppet_type)
          end

          def providers
            @providers ||= hashes_for_reg_type(:puppet_provider)
          end

          def puppet_functions
            @puppet_functions ||= hashes_for_reg_type(:puppet_function)
          end

          def puppet_tasks
            @puppet_tasks ||= hashes_for_reg_type(:puppet_task)
          end

          def puppet_plans
            @puppet_plans ||= hashes_for_reg_type(:puppet_plan)
          end

          def to_h
            {
              puppet_classes: puppet_classes,
              data_types: data_types,
              data_type_aliases: data_type_aliases,
              defined_types: defined_types,
              resource_types: resource_types,
              providers: providers,
              puppet_functions: puppet_functions,
              puppet_tasks: puppet_tasks,
              puppet_plans: puppet_plans
            }
          end

          private

          def hashes_for_reg_type(reg_type)
            all_to_h(registry.select { |i| i.type == reg_type })
          end

          def all_to_h(objects)
            objects.sort_by(&:name).map(&:to_hash)
          end

          def yard_args(patterns, debug: false, quiet: false)
            args = ['doc', '--no-progress', '-n']
            args << '--debug' if debug && !quiet
            args << '--backtrace' if debug && !quiet
            args << '-q' if quiet
            args << '--no-stats' if quiet
            args += patterns
            args
          end
        end

        # Generates markdown for Puppet classes based on Puppet Strings JSON
        # class PuppetClassMarkdown
        #   def initialize(puppet_classes, md, opts: {})
        #     @puppet_classes = puppet_classes
        #     @md = md
        #     @opts = opts
        #   end

        #   def generate!
        #     @puppet_classes.each do |puppet_class|
        #       @md.add_h2(puppet_class['name'])
        #       @md.add_paragraph("File(Line): `#{puppet_class['file']}(#{puppet_class['line']})`")

        #   private

        #   def doc_string_builder(puppet_class)
        #     return if puppet_class['docstring'].nil? || puppet_class['docstring'].empty?
        # end

        # Generates markdown for a control
        class ControlMarkdown
          def initialize(control, md, strings, module_name, framework, formatter: nil, opts: {})
            @control = control
            @md = md
            @strings = strings
            @module_name = module_name
            @framework = framework
            @formatter = formatter.nil? ? TypeExprValueFormatter : formatter
            @opts = opts
            @valid_level = []
            @valid_profile = []
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

          # This function act as a filter for controls based on the profile and level selections.
          # There are few scanarios that can happen:
          # 1. If no selections are made for profile or level, then all profiles and levels of control will be selected.
          # 2. If selections are made for profile, then only the selected profile and all levels of control will be selected.
          # 3. If selections are made for level, then only the selected level and all profiles of control will be selected.
          # This function adds in some runtime overhead because we're checking each control's level and profile which is
          # what we're going to be doing later when building the level and profile markdown, but this is
          # necessary to ensure that the reference.md is generated the way we want it to be.
          def verify_profile_and_level_selections
            return true if @opts[:select_profile].nil? && @opts[:select_level].nil?

            if @opts[:select_profile].nil? && !@opts[:select_level].nil?
              @control.levels.each do |level|
                @valid_level << level if select_control_level(level)
              end

              return true unless @valid_level.empty?
            elsif !@opts[:select_profile].nil? && @opts[:select_level].nil?
              @control.profiles.each do |profile|
                @valid_profile << profile if select_control_profile(profile)
              end

              return true unless @valid_profile.empty?
            elsif !@opts[:select_profile].nil? && !@opts[:select_level].nil?
              @control.levels.each do |level|
                @valid_level << level if select_control_level(level)
              end

              @control.profiles.each do |profile|
                @valid_profile << profile if select_control_profile(profile)
              end

              # As long as there are valid profiles and levels for the control at this stage, all is good
              !@valid_level.empty? && !@valid_profile.empty?
            end
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
            return true if @control.params? || @control.resource.sce_options? || @control.resource.sce_protected?
            return true if @control.resource.manifest? && @control.resource.manifest.declaration.parameters?

            false
          end

          def resource_param(ctrl_param)
            return unless @control.resource.manifest?

            @control.resource.manifest.declaration.parameters&.find { |x| x.name == "$#{ctrl_param[:name]}" }
          end

          def param_type_expr(ctrl_param, rsrc_param)
            @control_data[ctrl_param[:name]] = {} unless @control_data.key?(ctrl_param[:name])
            @control_data[ctrl_param[:name]][:type_expr] =
              rsrc_param&.type_expr? ? rsrc_param&.type_expr : ctrl_param[:type]
            return unless @control_data[ctrl_param[:name]][:type_expr]

            " - [ #{@md.code(@control_data[ctrl_param[:name]][:type_expr])} ]"
          end

          def param_default_value(ctrl_param, rsrc_param)
            @control_data[ctrl_param[:name]] = {} unless @control_data.key?(ctrl_param[:name])
            @control_data[ctrl_param[:name]][:default] = ctrl_param[:default] || rsrc_param&.value
            return unless @control_data[ctrl_param[:name]][:default]

            " - #{@md.italic('Default:')} #{@md.code(@control_data[ctrl_param[:name]][:default])}"
          end

          def param_description(ctrl_param)
            res = if @control.resource.type == 'class'
                    @strings.find_resource(@control.resource.title)
                  else
                    @strings.find_resource(@control.resource.type)
                  end
            return unless res&.key?(:docstring) && res[:docstring].key?(:tags)
            return if res[:docstring][:tags].empty? || res[:docstring][:tags].none? { |x| x[:tag_name] == 'param' }

            param_tag = res[:docstring][:tags].find { |x| x[:tag_name] == 'param' && x[:name] == ctrl_param[:name] }
            if param_tag.nil? || param_tag[:text].nil? || param_tag[:text].chomp.empty?
              if @opts[:strict]
                raise "No description found for parameter #{ctrl_param[:name]} in resource #{@control.resource.title}"
              end

              return
            end

            " - #{param_tag[:text]}"
          end

          def control_params_builder
            return unless control_has_valid_params?

            @md.add_h3('Parameters:')
            [@control.param_hashes, @control.resource.sce_options, @control.resource.sce_protected].each do |collection|
              collection.each do |hsh|
                rparam = resource_param(hsh)
                str_array = [@md.code(hsh[:name]), param_type_expr(hsh, rparam), param_default_value(hsh, rparam)]
                desc = param_description(hsh)
                str_array << desc if desc
                @md.add_ul(str_array.compact.join, indent: 1)
              end
            end
          end

          def control_levels_builder
            return unless @control.levels

            # @valid_level is populated in verify_profile_and_level_selections from the fact that we've given
            # the generator a list of levels we want to use. If we didn't give it a list of levels, then we
            # want to use all of the levels that the control supports from @control.
            if @framework == 'stig'
              @md.add_h3('Supported MAC Levels:')
            else
              @md.add_h3('Supported Levels:')
            end

            if @valid_level.empty?
              @control.levels.each do |l|
                @md.add_ul(@md.code(l), indent: 1)
              end
            else
              @valid_level.each do |l|
                @md.add_ul(@md.code(l), indent: 1)
              end
            end
          end

          def control_profiles_builder
            return unless @control.profiles

            # @valid_profile is populated in verify_profile_and_level_selections from the fact that we've given
            # the generator a list of profiles we want to use. If we didn't give it a list of profiles, then we
            # want to use all of the profiles that the control supports from @control.
            if @framework == 'stig'
              @md.add_h3('Supported Confidentiality:')
            else
              @md.add_h3('Supported Profiles:')
            end

            if @valid_profile.empty?
              @control.profiles.each do |l|
                @md.add_ul(@md.code(l), indent: 1)
              end
            else
              @valid_profile.each do |l|
                @md.add_ul(@md.code(l), indent: 1)
              end
            end
          end

          def control_alternate_ids_builder
            # return if @framework == 'stig'

            @md.add_h3('Alternate Config IDs:')
            @control.alternate_ids.each do |l|
              @md.add_ul(@md.code(l), indent: 1)
            end
          end

          # Function that returns true if the profile is in the list of profiles that we want to use.
          # @param profile [String] the profile to filter
          def select_control_profile(profile)
            @opts[:select_profile].include? profile
          end

          # Function that returns true if the level is in the list of levels that we want to use.
          # @param level [String] the level to filter
          def select_control_level(level)
            @opts[:select_level].include? level
          end

          def dependent_controls_builder
            dep_ctrls = @control.resource.dependent_controls
            return if dep_ctrls.nil? || dep_ctrls.empty?

            @md.add_h3('Dependent controls:')
            dep_ctrls.each do |ctrl|
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
            out_str.unshift("#{@module_name.split('-').last}::config:")
            @md.add_h3('Hiera Configuration Example:')
            @md.add_code_block(out_str.join("\n"), language: 'yaml')
          rescue StandardError => e
            err_msg = [
              "Failed to generate config example for control #{@control.id}",
              "Error: #{e.message}",
              "Control: Data #{@control_data.inspect}",
              e.backtrace.join("\n")
            ].join("\n")
            raise ConfigExampleError, err_msg
          end

          def resource_reference_builder
            @md.add_h3('Resource:')
            @md.add_ul(@md.code(@control.resource.to_reference), indent: 1)
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
