# frozen_string_literal: true

require 'cmdparse'
require 'abide_dev_utils/version'
require 'abide_dev_utils/constants'
require 'abide_dev_utils/cli/comply'
require 'abide_dev_utils/cli/puppet'
require 'abide_dev_utils/cli/xccdf'
require 'abide_dev_utils/cli/test'
require 'abide_dev_utils/cli/jira'

module Abide
  module CLI
    include AbideDevUtils::CliConstants
    ROOT_CMD_NAME = 'abide'
    ROOT_CMD_BANNER = 'Developer tools for Abide'

    def self.new_parser
      parser = CmdParse::CommandParser.new(handle_exceptions: true)
      parser.main_options.program_name = ROOT_CMD_NAME
      parser.main_options.version = AbideDevUtils::VERSION
      parser.main_options.banner = ROOT_CMD_BANNER
      parser.add_command(CmdParse::HelpCommand.new, default: true)
      parser.add_command(CmdParse::VersionCommand.new(add_switches: true))
      parser.add_command(ComplyCommand.new)
      parser.add_command(PuppetCommand.new)
      parser.add_command(XccdfCommand.new)
      parser.add_command(TestCommand.new)
      parser.add_command(JiraCommand.new)
      parser
    end

    def self.execute
      parser = new_parser
      parser.parse
    end
  end
end
