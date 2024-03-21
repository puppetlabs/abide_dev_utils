# frozen_string_literal: true

require 'abide_dev_utils/config'

module Abide
  module CLI
    # @abstract
    class AbideCommand < CmdParse::Command
      include AbideDevUtils::Config

      def initialize(cmd_name, cmd_short, cmd_long, **opts)
        super(cmd_name, takes_commands: opts.fetch(:takes_commands, false))
        @deprecated = opts.fetch(:deprecated, false)
        if @deprecated
          cmd_short = "[DEPRECATED] #{cmd_short}"
          cmd_long = "[DEPRECATED] #{cmd_long}"
        end
        short_desc(cmd_short)
        long_desc(cmd_long)
        add_command(CmdParse::HelpCommand.new, default: true) if opts[:takes_commands]
      end

      def on_after_add
        return unless super_command.respond_to?(:deprecated?) && super_command.deprecated?

        short_desc("[DEPRECATED BY PARENT] #{@short_desc}")
        long_desc("[DEPRECATED BY PARENT] #{@long_desc}")
      end

      def deprecated?
        @deprecated
      end
    end
  end
end
