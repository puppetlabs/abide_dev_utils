# frozen_string_literal: true

require 'abide_dev_utils/cli/abstract'
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
        add_command(XccdfDiffCommand.new)
        add_command(XccdfGenMapCommand.new)
      end
    end

    class XccdfGenMapCommand < CmdParse::Command
      CMD_NAME = 'gen-map'
      CMD_SHORT = 'Generates mappings from XCCDF files'
      CMD_LONG = 'Generates mappings for CEM modules from 1 or more XCCDF files as YAML'
      def initialize
        super(CMD_NAME, takes_commands: false)
        short_desc(CMD_SHORT)
        long_desc(CMD_LONG)
        options.on('-b [TYPE]', '--benchmark-type [TYPE]', 'XCCDF Benchmark type CIS by default') { |b| @data[:type] = b }
        options.on('-d [DIR]', '--files-output-directory [DIR]', 'Directory to save files data/mappings by default') { |d| @data[:dir] = d }
        options.on('-q', '--quiet', 'Show no output in the terminal') { @data[:quiet] = true }
        options.on('-p [PREFIX]', '--parent-key-prefix [PREFIX]', 'A prefix to append to the parent key') do |p|
          @data[:parent_key_prefix] = p
        end
      end

      def execute(xccdf_file)
        if @data[:quiet] && !@data[:dir]
          AbideDevUtils::Output.simple("I don\'t know how to quietly output to the console\n¯\\_(ツ)_/¯") 
          exit 1
        end
        @data[:console] = true if @data[:dir].nil?
        @data[:type] = 'cis' if @data[:type].nil?
        @data[:parent_key_prefix] = '' if @data[:parent_key_prefix].nil?
        hfile = AbideDevUtils::XCCDF.gen_map(xccdf_file, **@data)
        mapping_dir = File.dirname(hfile.keys[0]) unless @data[:dir].nil?
        AbideDevUtils::Output.simple("Creating directory #{mapping_dir}") unless @data[:quiet] || @data[:console] || @data[:dir].nil? || File.directory?(mapping_dir)
        FileUtils.mkdir_p(mapping_dir) unless @data[:console] || @data[:dir].nil?
        hfile.each do |key, val|
          file_path = @data[:dir].nil? ? nil : key
          AbideDevUtils::Output.yaml(val, console: @data[:console], file: file_path)
        end
      end
    end

    class XccdfToHieraCommand < CmdParse::Command
      CMD_NAME = 'to-hiera'
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
        hfile = AbideDevUtils::XCCDF.to_hiera(xccdf_file, @data)
        AbideDevUtils::Output.yaml(hfile, console: @data[:file].nil?, file: @data[:file])
      end
    end

    class XccdfDiffCommand < AbideCommand
      CMD_NAME = 'diff'
      CMD_SHORT = 'Generates a diff report between two XCCDF files'
      CMD_LONG = 'Generates a diff report between two XCCDF files'
      CMD_FILE1_ARG = 'path to first XCCDF file'
      CMD_FILE2_ARG = 'path to second XCCDF file'
      def initialize
        super(CMD_NAME, CMD_SHORT, CMD_LONG, takes_commands: false)
        argument_desc(FILE1: CMD_FILE1_ARG, FILE2: CMD_FILE2_ARG)
        options.on('-o [PATH]', '--out-file', 'Save the report as a yaml file') { |x| @data[:outfile] = x }
        options.on('-p [PROFILE]', '--profile', 'Only diff and specific profile in the benchmarks') do |x|
          @data[:profile] = x
        end
        options.on('-q', '--quiet', 'Show no output in the terminal') { @data[:quiet] = false }
        options.on('--no-diff-profiles', 'Do not diff the profiles in the XCCDF files') { @data[:diff_profiles] = false }
        options.on('--no-diff-controls', 'Do not diff the controls in the XCCDF files') { @data[:diff_controls] = false }
      end

      def execute(file1, file2)
        diffreport = AbideDevUtils::XCCDF.diff(file1, file2, @data)
        AbideDevUtils::Output.yaml(diffreport, console: @data.fetch(:quiet, true), file: @data.fetch(:outfile, nil))
      end
    end
  end
end
