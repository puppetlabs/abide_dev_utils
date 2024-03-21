# frozen_string_literal: true

require 'abide_dev_utils/sce'
require 'abide_dev_utils/files'
require 'abide_dev_utils/output'
require 'abide_dev_utils/validate'
require 'abide_dev_utils/xccdf/diff'
require 'abide_dev_utils/cli/abstract'

module Abide
  module CLI
    class SceCommand < AbideCommand
      CMD_NAME = 'sce'
      CMD_SHORT = 'Commands related to Puppet SCE'
      CMD_LONG = 'Namespace for commands related to Puppet SCE'
      def initialize
        super(CMD_NAME, CMD_SHORT, CMD_LONG, takes_commands: true)
        add_command(SceGenerate.new)
        add_command(SceUpdateConfig.new)
        add_command(SceValidate.new)
      end
    end

    class SceGenerate < AbideCommand
      CMD_NAME = 'generate'
      CMD_SHORT = 'Holds subcommands for generating objects / files'
      CMD_LONG = 'Holds subcommands for generating objects / files'
      def initialize
        super(CMD_NAME, CMD_SHORT, CMD_LONG, takes_commands: true)
        add_command(SceGenerateCoverageReport.new)
        add_command(SceGenerateReference.new)
      end
    end

    class SceGenerateCoverageReport < AbideCommand
      CMD_NAME = 'coverage-report'
      CMD_SHORT = 'Generates control coverage report'
      CMD_LONG = <<-EOLC.chomp
      Generates report of resources that are associated with controls in mapping data. This command must
      be run from a module directory.
      EOLC
      def initialize
        super(CMD_NAME, CMD_SHORT, CMD_LONG, takes_commands: false)
        options.on('-o [FILE]', '--out-file [FILE]', 'Path to save the coverage report') { |f| @data[:file] = f }
        options.on('-f [FORMAT]', '--format [FORMAT]', 'The format to output the report in (hash, json, yaml)') do |f|
          @data[:format] = f
        end
        options.on('-B [BENCHMARK]', '--benchmark [BENCHMARK]', 'Specify the benchmark to show coverage for') do |x|
          @data[:benchmark] = x
        end
        options.on('-P [PROFILE]', '--profile [PROFILE]', 'Specifiy the profile to show coverage for') do |x|
          @data[:profile] = x
        end
        options.on('-L [LEVEL]', '--level [LEVEL]', 'Specify the level to show coverage for') do |l|
          @data[:level] = l
        end
        options.on('-I', '--ignore-benchmark-errors', 'Ignores errors while generating benchmark reports') do
          @data[:ignore_all] = true
        end
        options.on('-X [XCCDF_DIR]', '--xccdf-dir [XCCDF_DIR]',
                   'If specified, the coverage report will be correlated with info from the benchmark XCCDF files') do |d|
          @data[:xccdf_dir] = d
        end
        options.on('-v', '--verbose', 'Will output the report to the console') { @data[:verbose] = true }
        options.on('-q', '--quiet', 'Will not output anything to the console') { @data[:quiet] = true }
      end

      def execute
        file_name = @data.fetch(:file, 'coverage_report')
        out_format = @data.fetch(:format, 'yaml')
        quiet = @data.fetch(:quiet, false)
        console = @data.fetch(:verbose, false) && !quiet
        generate_opts = {
          benchmark: @data[:benchmark],
          profile: @data[:profile],
          level: @data[:level],
          ignore_benchmark_errors: @data.fetch(:ignore_all, false),
          xccdf_dir: @data[:xccdf_dir]
        }
        AbideDevUtils::Output.simple('Generating coverage report...') unless quiet
        coverage = AbideDevUtils::Sce::Generate::CoverageReport.generate(format_func: :to_h, opts: generate_opts)
        AbideDevUtils::Output.simple("Saving coverage report to #{file_name}...")
        case out_format
        when /yaml/i
          AbideDevUtils::Output.yaml(coverage, console: console, file: file_name)
        when /json/i
          AbideDevUtils::Output.json(coverage, console: console, file: file_name)
        else
          File.open(file_name, 'w') do |f|
            AbideDevUtils::Output.simple(coverage.to_s, stream: f)
          end
        end
      end
    end

    class SceGenerateReference < AbideCommand
      CMD_NAME = 'reference'
      CMD_SHORT = 'Generates a reference doc for the module'
      CMD_LONG = 'Generates a reference doc for the module'
      def initialize
        super(CMD_NAME, CMD_SHORT, CMD_LONG, takes_commands: false)
        options.on('-o [FILE]', '--out-file [FILE]', 'Path to save the updated config file') do |o|
          @data[:out_file] = o
        end
        options.on('-f [FORMAT]', '--format [FORMAT]', 'Format to save reference as') do |f|
          @data[:format] = f
        end
        options.on('-v', '--verbose', 'Verbose output') do
          @data[:debug] = true
        end
        options.on('-q', '--quiet', 'Quiet output') do
          @data[:quiet] = true
        end
        options.on('-s', '--strict', 'Fails if there are any errors') do
          @data[:strict] = true
        end
        options.on('-p [PROFILE]', '--select-profile [PROFILE]',
                   'The list of profiles that the reference.md will use separated by commas') do |pr|
          @data[:select_profile] = pr.split(',')
        end
        options.on('-l [LEVEL]', '--select-level [LEVEL]',
                   'The list of level that the reference.md will use separated by commas') do |l|
          @data[:select_level] = l.split(',')
        end
      end

      def execute
        AbideDevUtils::Validate.puppet_module_directory
        AbideDevUtils::Sce::Generate::Reference.generate(@data)
      end
    end

    class SceUpdateConfig < AbideCommand
      CMD_NAME = 'update-config'
      CMD_SHORT = 'Updates the Puppet SCE config'
      CMD_LONG = 'Updates the Puppet SCE config'
      def initialize
        super(CMD_NAME, CMD_SHORT, CMD_LONG, takes_commands: true)
        add_command(SceUpdateConfigFromDiff.new)
      end
    end

    class SceUpdateConfigFromDiff < AbideCommand
      CMD_NAME = 'from-diff'
      CMD_SHORT = 'Update by diffing two XCCDF files'
      CMD_LONG = 'Update by diffing two XCCDF files'
      CMD_CONFIG_FILE = 'Path to the Puppet SCE config file'
      CMD_CURRENT_XCCDF = 'Path to the current XCCDF file'
      CMD_NEW_XCCDF = 'Path to the new XCCDF file'
      def initialize
        super(CMD_NAME, CMD_SHORT, CMD_LONG, takes_commands: false)
        argument_desc(CONFIG_FILE: CMD_CONFIG_FILE, CURRENT_XCCDF: CMD_CURRENT_XCCDF, NEW_XCCDF: CMD_NEW_XCCDF)
        options.on('-o [FILE]', '--out-file [FILE]', 'Path to save the updated config file') do |o|
          @data[:out_file] = o
        end
        options.on('-v', '--verbose', 'Verbose output') do
          @data[:verbose] = true
        end
        options.on('-q', '--quiet', 'Quiet output') do
          @data[:quiet] = true
        end
      end

      def help_arguments
        <<~ARGHELP
          Arguments:
            CONFIG_FILE:   #{CMD_CONFIG_FILE}
            CURRENT_XCCDF: #{CMD_CURRENT_XCCDF}
            NEW_XCCDF:     #{CMD_NEW_XCCDF}
        ARGHELP
      end

      def execute(_config_file, _cur_xccdf, _new_xccdf)
        warn 'This command is currently non-functional'
        # AbideDevUtils::Validate.file(config_file, extension: 'yaml')
        # AbideDevUtils::Validate.file(cur_xccdf, extension: 'xml')
        # config_hiera = AbideDevUtils::Files::Reader.read(config_file, safe: true)
        # diff = AbideDevUtils::XCCDF::Diff::BenchmarkDiff.new(cur_xccdf, new_xccdf).diff[:diff][:number_title]
        # new_config_hiera, change_report = AbideDevUtils::Sce.update_legacy_config_from_diff(config_hiera, diff)
        # AbideDevUtils::Output.yaml(new_config_hiera, console: @data[:verbose], file: @data[:out_file])
        # AbideDevUtils::Output.simple(change_report) unless @data[:quiet]
      end
    end

    class SceValidate < AbideCommand
      CMD_NAME = 'validate'
      CMD_SHORT = 'Validation commands for SCE modules'
      CMD_LONG = 'Validation commands for SCE modules'
      def initialize
        super(CMD_NAME, CMD_SHORT, CMD_LONG, takes_commands: true)
        add_command(SceValidatePuppetStrings.new)
      end
    end

    class SceValidatePuppetStrings < AbideCommand
      CMD_NAME = 'puppet-strings'
      CMD_SHORT = 'Validates the Puppet Strings documentation'
      CMD_LONG = 'Validates the Puppet Strings documentation'
      def initialize
        super(CMD_NAME, CMD_SHORT, CMD_LONG, takes_commands: false)
        options.on('-v', '--verbose', 'Verbose output') do
          @data[:verbose] = true
        end
        options.on('-q', '--quiet', 'Quiet output') do
          @data[:quiet] = true
        end
        options.on('-f [FORMAT]', '--format [FORMAT]', 'Format for output (text, json, yaml)') do |f|
          @data[:format] = f
        end
        options.on('-o [FILE]', '--out-file [FILE]', 'Path to save the updated config file') do |o|
          @data[:out_file] = o
        end
        options.on('-s', '--strict', 'Exits with exit code 1 if there are any warnings') do
          @data[:strict] = true
        end
      end

      def execute
        @data[:format] ||= 'text'
        AbideDevUtils::Validate.puppet_module_directory
        output = AbideDevUtils::Sce::Validate::Strings.validate(**@data)
        has_errors = false
        has_warnings = false
        output.each do |_, i|
          has_errors = true if i.any? { |j| j[:errors].any? }
          has_warnings = true if i.any? { |j| j[:warnings].any? }
        end
        AbideDevUtils::Output.send(
          @data[:format].to_sym,
          output,
          console: !@data[:quiet],
          file: @data[:out_file],
          stringify: true
        )
        exit 1 if has_errors || (has_warnings && @data[:strict])
      end
    end
  end
end
