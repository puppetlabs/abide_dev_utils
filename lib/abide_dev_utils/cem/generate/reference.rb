# frozen_string_literal: true

require 'json'
require 'yaml'
require 'abide_dev_utils/markdown'
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
            MarkdownGenerator.new(benchmarks).generate(doc_title)
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
      end
    end
  end
end
