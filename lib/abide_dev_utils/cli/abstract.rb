# frozen_string_literal: true

require 'abide_dev_utils/config'

module Abide
  module CLI
    # @abstract
    class AbideCommand < CmdParse::Command
      include AbideDevUtils::Config
      def initialize(cmd_name, cmd_short, cmd_long, **opts)
        super(cmd_name, **opts)
        short_desc(cmd_short)
        long_desc(cmd_long)
        add_command(CmdParse::HelpCommand.new, default: true) if opts[:takes_commands]
      end
    end
  end
end
