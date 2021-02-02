# frozen_string_literal: true

require 'abide_dev_utils/cli/abstract'

module Abide
  module CLI
    class PuppetCommand < Command
      CMD_NAME = 'puppet'
      CMD_SHORT = 'Commands related to Puppet code'
      CMD_LONG = 'Namespace for commands related to Puppet code'
      def initialize
        super(CMD_NAME, CMD_SHORT, CMD_LONG, takes_commands: true)
        add_command(PuppetCoverageCommand.new)
        add_command(PuppetNewCommand.new)
      end
    end

    class PuppetCoverageCommand < Command
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
        require 'abide_dev_utils/ppt'
        Abide::CLI::VALIDATE.directory(class_dir)
        Abide::CLI::VALIDATE.file(hiera_file)
        coverage = AbideDevUtils::Ppt::CoverageReport.generate(class_dir, hiera_file, @data[:profile])
        coverage.each do |k, v|
          next if ['classes', 'benchmark'].include?(k)

          Abide::CLI::OUTPUT.simple("#{k} coverage: #{v[:coverage]}%")
        end
        return if @data[:file].nil?

        Abide::CLI::OUTPUT.json(coverage, file: @data[:file])
      end
    end

    class PuppetNewCommand < Command
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
      end

      def execute(type, name)
        require 'abide_dev_utils/ppt/new_obj'
        builder = AbideDevUtils::Ppt::NewObjectBuilder.new(
          type,
          name,
          opts: @data,
          vars: @data.fetch(:vars, '').split(',').map { |i| i.split('=') }.to_h # makes the str a hash
        )
        result = builder.build
        Abide::CLI::OUTPUT.simple(result)
      end
    end
  end
end
