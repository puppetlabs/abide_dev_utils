# frozen_string_literal: true

require 'abide_dev_utils/xccdf'

module Abide
  module CLI
    class XccdfCommand < CmdParse::Command
      CMD_NAME = 'xccdf'
      CMD_SHORT = 'Commands related to XCCDF files'
      CMD_LONG = 'Namespace for commands related to XCCDF files'
      def initialize
        super(CMD_NAME, takes_commands: true)
        short_desc(CMD_SHORT)
        long_desc(CMD_LONG)
        add_command(CmdParse::HelpCommand.new, default: true)
        add_command(XccdfToHieraCommand.new)
      end
    end

    class XccdfToHieraCommand < CmdParse::Command
      CMD_NAME = 'to_hiera'
      CMD_SHORT = 'Generates control coverage report'
      CMD_LONG = 'Generates report of valid Puppet classes that match with Hiera controls'
      def initialize
        super(CMD_NAME, takes_commands: false)
        short_desc(CMD_SHORT)
        long_desc(CMD_LONG)
        options.on('-b [TYPE]', '--benchmark-type [TYPE]', 'XCCDF Benchmark type') { |b| @data[:type] = b }
        options.on('-o [FILE]', '--out-file [FILE]', 'Path to save file') { |f| @data[:file] = f }
        options.on('-p [PREFIX]', '--parent-key-prefix [PREFIX]', 'A prefix to append to the parent key') do |p|
          @data[:parent_key_prefix] = p
        end
        options.on('-N', '--number-fmt', 'Format Hiera control names based off of control number instead of name.') do
          @data[:num] = true
        end
      end

      def execute(xccdf_file)
        @data[:type] = 'cis' if @data[:type].nil?

        to_hiera(xccdf_file)
      end

      private

      def to_hiera(xccdf_file)
        xfile = AbideDevUtils::XCCDF.to_hiera(xccdf_file, @data)
        Abide::CLI::OUTPUT.yaml(xfile, console: @data[:file].nil?, file: @data[:file])
      end
    end
  end
end
