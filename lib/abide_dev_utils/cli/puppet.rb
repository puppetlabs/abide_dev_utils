# frozen_string_literal: true

module Abide
  module CLI
    class PuppetCommand < CmdParse::Command
      CMD_NAME = 'puppet'
      CMD_SHORT = 'Commands related to Puppet code'
      CMD_LONG = 'Namespace for commands related to Puppet code'
      def initialize
        super(CMD_NAME, takes_commands: true)
        short_desc(CMD_SHORT)
        long_desc(CMD_LONG)
        add_command(CmdParse::HelpCommand.new, default: true)
        add_command(PuppetCoverageCommand.new)
      end
    end

    class PuppetCoverageCommand < CmdParse::Command
      CMD_NAME = 'coverage'
      CMD_SHORT = 'Generates control coverage report'
      CMD_LONG = 'Generates report of valid Puppet classes that match with Hiera controls'
      CMD_CLASS_DIR = 'Directory that holds Puppet manifests'
      CMD_HIERA_FILE = 'Hiera file generated from an XCCDF'
      def initialize
        super(CMD_NAME, takes_commands: false)
        short_desc(CMD_SHORT)
        long_desc(CMD_LONG)
        argument_desc(CLASS_DIR: CMD_CLASS_DIR, HIERA_FILE: CMD_HIERA_FILE)
        options.on('-o [FILE]', '--out-file [FILE]', 'Path to save the coverage report') { |f| @data[:file] = f }
        options.on('-p [PROFILE]', '--profile [PROFILE]', 'Generate only for profile') { |p| @data[:profile] = p }
      end

      def help_arguments
        <<~ARGHELP
          Arguments:
              CLASS_DIR        #{CMD_CLASS_DIR}
              HIERA_FILE       #{CMD_HIERA_FILE}

        ARGHELP
      end

      def execute(class_dir, hiera_file)
        require 'abide_dev_utils/ppt'
        Abide::CLI::VALIDATE.directory(class_dir)
        Abide::CLI::VALIDATE.file(hiera_file)
        coverage = AbideDevUtils::Ppt.coverage_report(class_dir, hiera_file, @data[:profile])
        coverage.each do |k, v|
          next if ['classes', 'benchmark'].include?(k)

          Abide::CLI::OUTPUT.simple("#{k} coverage: #{v[:coverage]}%")
        end
        return if @data[:file].nil?

        Abide::CLI::OUTPUT.json(coverage, file: @data[:file])
      end
    end
  end
end
