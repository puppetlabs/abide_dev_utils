# frozen_string_literal: true

require 'abide_dev_utils/cli/abstract'
require 'abide_dev_utils/output'
require 'abide_dev_utils/ppt'

module Abide
  module CLI
    class PuppetCommand < AbideCommand
      CMD_NAME = 'puppet'
      CMD_SHORT = 'Commands related to Puppet code'
      CMD_LONG = 'Namespace for commands related to Puppet code'
      def initialize
        super(CMD_NAME, CMD_SHORT, CMD_LONG, takes_commands: true)
        add_command(PuppetCoverageCommand.new)
        add_command(PuppetNewCommand.new)
        add_command(PuppetRenameCommand.new)
        add_command(PuppetFixClassNamesCommand.new)
        add_command(PuppetAuditClassNamesCommand.new)
      end
    end

    class PuppetCoverageCommand < AbideCommand
      CMD_NAME = 'coverage'
      CMD_SHORT = 'Generates control coverage report'
      CMD_LONG = 'Generates report of valid Puppet classes that match with Hiera controls'
      CMD_CLASS_DIR = 'Directory that holds Puppet manifests'
      CMD_HIERA_FILE = 'Hiera file generated from an XCCDF'
      def initialize
        super(CMD_NAME, CMD_SHORT, CMD_LONG, takes_commands: false)
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
        require 'abide_dev_utils/ppt/coverage'
        Abide::CLI::VALIDATE.directory(class_dir)
        Abide::CLI::VALIDATE.file(hiera_file)
        coverage = AbideDevUtils::Ppt.generate_coverage_report(class_dir, hiera_file, @data[:profile])
        coverage.each do |k, v|
          next if k.match?(/classes|benchmark/)

          Abide::CLI::OUTPUT.simple("#{k} coverage: #{v[:coverage]}%")
        end
        return if @data[:file].nil?

        Abide::CLI::OUTPUT.json(coverage, file: @data[:file])
      end
    end

    class PuppetNewCommand < AbideCommand
      CMD_NAME = 'new'
      CMD_SHORT = 'Generates a new Puppet object from templates'
      CMD_LONG = 'Generates a new Puppet object (class, test, etc.) from templates stored in the module repo'
      CMD_TYPE_ARG = 'The type of object to generate. This value must be the name of a template (without .erb) file in <template dir>'
      CMD_NAME_ARG = 'The fully namespaced name of the new object'
      def initialize
        super(CMD_NAME, CMD_SHORT, CMD_LONG, takes_commands: false)
        argument_desc(TYPE: CMD_TYPE_ARG, NAME: CMD_NAME_ARG)
        options.on(
          '-t [DIR]',
          '--template-dir [DIR]',
          'Path to the directory holding your ERB templates for custom objects. Defaults to "object_templates" in the root dir.'
        ) { |t| @data[:tmpl_dir] = t }
        options.on(
          '-r [DIR]',
          '--root-dir [DIR]',
          'Path to the root directory of the module. Defaults to the current working directory.'
        ) { |r| @data[:root_dir] = r }
        options.on(
          '-A',
          '--absolute-template-dir',
          'Use this flage if the template dir is an absolute path'
        ) { |a| @data[:absolute_template_dir] = a }
        options.on(
          '-n [NAME]',
          '--template-name [NAME]',
          'Allows you to specify a name for the template if it is different from the basename (last segment) of the object name.'
        )
        options.on(
          '-V [VARNAME=VALUE]',
          '--vars [VARNAME=VALUE]',
          'Allows you to specify comma-separated variable names and values that will be converted into a hash that is available for you to use in your templates'
        ) { |v| @data[:vars] = v }
        options.on(
          '-S [PATH]',
          '--spec-template [PATH]',
          'Path to an ERB template to use for rspec test generation instead of the default'
        )
        options.on(
          '-f',
          '--force',
          'Skips any prompts and executes the command'
        ) { |_| @data[:force] = true }
      end

      def execute(type, name)
        AbideDevUtils::Ppt.build_new_object(type, name, @data)
      end
    end

    class PuppetRenameCommand < AbideCommand
      CMD_NAME = 'rename'
      CMD_SHORT = 'Renames a Puppet class'
      CMD_LONG = 'Renames a Puppet class. It does this by renaming the file and also the class name in the file. This command can also move class files based on the new class name.'
      CMD_FROM_ARG = 'The current full class name'
      CMD_TO_ARG = 'The new full class name'
      def initialize
        super(CMD_NAME, CMD_SHORT, CMD_LONG, takes_commands: false)
        argument_desc(FROM: CMD_FROM_ARG, TO: CMD_TO_ARG)
        options.on(
          '-d',
          '--declaration-only',
          'Will not rename the class file, only the class declaration in the file'
        ) { @data[:declaration_only] = true }
        options.on(
          '-t',
          '--declaration-in-to-file',
          'Use the path derived from the TO class name as the existing file path when renaming class declaration'
        ) { @data[:declaration_in_to_file] = true }
        options.on(
          '-f',
          '--force',
          'Forces file move operations'
        ) { @data[:force] = true }
        options.on(
          '-v',
          '--verbose',
          'Sets verbose mode on file operations'
        ) { @data[:verbose] = true }
      end

      def execute(from, to)
        AbideDevUtils::Ppt.rename_puppet_class(from, to, **@data)
      end
    end

    class PuppetFixClassNamesCommand < AbideCommand
      CMD_NAME = 'fix-class-names'
      CMD_SHORT = 'Fixes Puppet class names that are mismatched'
      CMD_LONG = 'Fixes Puppet class names that are mismatched'
      CMD_MODE_ARG = '"file" or "class". If "file", the file names will be changed to match their class declarations. If "class", the class declarations will be changed to match the file names.'
      CMD_DIR_ARG = 'The directory containing the Puppet class files'
      def initialize
        super(CMD_NAME, CMD_SHORT, CMD_LONG, takes_commands: false)
        argument_desc(MODE: CMD_MODE_ARG, DIR: CMD_DIR_ARG)
        options.on(
          '-f',
          '--force',
          'Forces file move operations'
        ) { @data[:force] = true }
        options.on(
          '-v',
          '--verbose',
          'Sets verbose mode on file operations'
        ) { @data[:verbose] = true }
      end

      def execute(mode, dir)
        case mode
        when /^f.*/
          AbideDevUtils::Ppt.fix_class_names_file_rename(dir, **@data)
        when /^c.*/
          AbideDevUtils::Ppt.fix_class_names_class_rename(dir, **@data)
        else
          raise ::ArgumentError, "Invalid mode. Mode:#{mode}"
        end
      end
    end

    class PuppetAuditClassNamesCommand < AbideCommand
      CMD_NAME = 'audit-class-names'
      CMD_SHORT = 'Finds Puppet classes in a directory that have names that do not match their path'
      CMD_LONG = 'Finds Puppet classes in a directory that have names that do not match their path. This is helpful because class names that do not match their path structure break Puppet autoloading.'
      CMD_DIR_ARG = 'The directory containing the Puppet class files'
      def initialize
        super(CMD_NAME, CMD_SHORT, CMD_LONG, takes_commands: false)
        argument_desc(DIR: CMD_DIR_ARG)
        options.on('-o [FILE]', '--out-file [FILE]', 'Save results to a file') { |f| @data[:file] = f }
        options.on('-q', '--quiet', 'Do not print results to console') { @data[:quiet] = true }
      end

      def execute(dir)
        if @data.fetch(:quiet, false) && !@data.key?(:file)
          AbideDevUtils::Output.simple('ERROR: Specifying --quiet without --out-file is useless.', stream: $stderr)
          exit 1
        end

        AbideDevUtils::Ppt.audit_class_names(dir, **@data)
      end
    end
  end
end
