# frozen_string_literal: true

require 'abide_dev_utils/cem'
require 'abide_dev_utils/files'
require 'abide_dev_utils/output'
require 'abide_dev_utils/validate'
require 'abide_dev_utils/xccdf/diff/benchmark'
require 'abide_dev_utils/cli/abstract'

module Abide
  module CLI
    class CemCommand < AbideCommand
      CMD_NAME = 'cem'
      CMD_SHORT = 'Commands related to Puppet CEM'
      CMD_LONG = 'Namespace for commands related to Puppet CEM'
      def initialize
        super(CMD_NAME, CMD_SHORT, CMD_LONG, takes_commands: true)
        add_command(CemUpdateConfig.new)
      end
    end

    class CemUpdateConfig < AbideCommand
      CMD_NAME = 'update-config'
      CMD_SHORT = 'Updates the Puppet CEM config'
      CMD_LONG = 'Updates the Puppet CEM config'
      def initialize
        super(CMD_NAME, CMD_SHORT, CMD_LONG, takes_commands: true)
        add_command(CemUpdateConfigFromDiff.new)
      end
    end

    class CemUpdateConfigFromDiff < AbideCommand
      CMD_NAME = 'from-diff'
      CMD_SHORT = 'Update by diffing two XCCDF files'
      CMD_LONG = 'Update by diffing two XCCDF files'
      CMD_CONFIG_FILE = 'Path to the Puppet CEM config file'
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

      def execute(config_file, cur_xccdf, new_xccdf)
        AbideDevUtils::Validate.file(config_file, extension: 'yaml')
        AbideDevUtils::Validate.file(cur_xccdf, extension: 'xml')
        config_hiera = AbideDevUtils::Files::Reader.read(config_file, safe: true)
        diff = AbideDevUtils::XCCDF::Diff::BenchmarkDiff.new(cur_xccdf, new_xccdf).diff[:diff][:number_title]
        new_config_hiera, change_report = AbideDevUtils::CEM.update_legacy_config_from_diff(config_hiera, diff)
        AbideDevUtils::Output.yaml(new_config_hiera, console: @data[:verbose], file: @data[:out_file])
        AbideDevUtils::Output.simple(change_report) unless @data[:quiet]
      end
    end
  end
end
