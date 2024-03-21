# frozen_string_literal: true

require 'abide_dev_utils/cli/abstract'

module Abide
  module CLI
    class TestCommand < AbideCommand
      CMD_NAME = 'test'
      CMD_SHORT = 'Run test suites against a Puppet module'
      CMD_LONG = 'Run various test suites against a Puppet module. Requires PDK to be installed.'
      CMD_PDK = 'command -v pdk'
      CMD_LIT_BASE = 'bundle exec rake'

      def initialize
        super(CMD_NAME, CMD_SHORT, CMD_LONG, takes_commands: false, deprecated: true)
        argument_desc(SUITE: 'Test suite to run [all, validate, unit, limus]')
        options.on('-p', '--puppet-version', 'Set Puppet version for unit tests. Takes SemVer string') do |p|
          @data[:puppet] = p
        end
        options.on('-e', '--pe-version', 'Set PE version for unit tests. Takes SemVer String') { |e| @data[:pe] = e }
        options.on('-n', '--no-teardown', 'Do not tear down Litmus machines after tests') do |_|
          @data[:no_teardown] = true
        end
        options.on('-c [puppet[67]]', '--collection [puppet[67]]', 'Puppet collection to use with litmus tests') do |c|
          @data[:collection] = c
        end
        options.on('-l [LIST]', '--provision-list [LIST]', 'Set the provision list for Litmus') do |l|
          @data[:provision_list] = l
        end
        options.on('-M [PATH]', '--module-dir [PATH]',
                   'Set a different directory as the module dir (defaults to current dir)') do |m|
          @data[:module_dir] = m
        end
        # Declare and setup commands
        @validate = ['validate', '--parallel']
        @unit = ['test', 'unit', '--parallel']
        # Add unit args if they exist
        @unit << "--puppet-version #{@data[:puppet]}" unless @data[:puppet].nil? && !@data[:pe].nil?
        @unit << "--pe-version #{@data[:pe]}" unless @data[:pe].nil?
        # Get litmus args and supply defaults if necessary
        litmus_pl = @data[:provision_list].nil? ? 'default' : @data[:provision_list]
        litmus_co = @data[:collection].nil? ? 'puppet6' : @data[:collection]
        # Now we craft the litmus commands
        @litmus_pr = [CMD_LIT_BASE, "'litmus:provision_list[#{litmus_pl}]'"]
        @litmus_ia = [CMD_LIT_BASE, "'litmus:install_agent[#{litmus_co}]'"]
        @litmus_im = [CMD_LIT_BASE, "'litmus:install_module'"]
        @litmus_ap = [CMD_LIT_BASE, "'litmus:acceptance:parallel'"]
        @litmus_td = [CMD_LIT_BASE, "'litmus:tear_down'"]
      end

      def execute(suite)
        validate_env_and_opts
        case suite.downcase
        when /^a[A-Za-z]*/
          run_command(@validate)
          run_command(@unit)
          run_litmus
        when /^v[A-Za-z]*/
          run_command(@validate)
        when /^u[A-Za-z]*/
          run_command(@unit)
        when /^l[A-Za-z]*/
          run_litmus
        else
          Abide::CLI::OUTPUT.simple("Suite #{suite} in invalid!")
          Abide::CLI::OUTPUT.simple('Valid options for TEST are [a]ll, [v]alidate, [u]nit, [l]itmus')
        end
      end

      private

      def validate_env_and_opts
        Abide::CLI::VALIDATE.directory(@data[:module_dir]) unless @data[:module_dir].nil?
        Abide::CLI::VALIDATE.not_empty(`#{CMD_PDK}`, 'PDK is required for running test suites!')
      end

      def run_litmus
        run_command(@litmus_pr)
        run_command(@litmus_ia)
        run_command(@litmus_im)
        run_command(@litmus_ap)
        run_command(@litmus_td) unless @data[:no_teardown]
      end

      def run_command(*args)
        arg_str = args.join(' ')
        if @data[:module_dir]
          `cd #{@data[:module_dir]} && $(#{CMD_PDK}) #{arg_str}`
        else
          `$(#{CMD_PDK}) #{arg_str}`
        end
      end
    end
  end
end
