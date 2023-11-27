# frozen_string_literal: true

require 'io/console'
require_relative 'output'

module AbideDevUtils
  module Prompt
    def self.yes_no(msg, auto_approve: false, stream: $stdout)
      prompt_msg = "#{msg} (Y/n): "
      if auto_approve
        AbideDevUtils::Output.simple("#{prompt_msg}Y", stream: stream)
        return true
      end

      AbideDevUtils::Output.print(prompt_msg, stream: stream)
      return true if $stdin.cooked(&:gets).match?(/^[Yy].*/)

      false
    end

    def self.single_line(msg, stream: $stdout)
      AbideDevUtils::Output.print("#{msg}: ", stream: stream)
      $stdin.cooked(&:gets).chomp
    end

    def self.username(stream: $stdout)
      AbideDevUtils::Output.print('Username: ', stream: stream)
      $stdin.cooked(&:gets).chomp
    end

    def self.password
      $stdin.getpass('Password:')
    end

    def self.secure(msg)
      $stdin.getpass(msg)
    end
  end
end
