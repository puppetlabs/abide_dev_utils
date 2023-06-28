# frozen_string_literal: true

require 'io/console'

module AbideDevUtils
  module Prompt
    def self.yes_no(msg, auto_approve: false)
      return true if auto_approve

      print "#{msg} (Y/n): "
      return true if $stdin.cooked(&:gets).match?(/^[Yy].*/)

      false
    end

    def self.single_line(msg)
      print "#{msg}: "
      $stdin.cooked(&:gets).chomp
    end

    def self.username
      print 'Username: '
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
