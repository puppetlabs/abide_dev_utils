# frozen_string_literal: true

require 'jira-ruby'
require_relative '../prompt'

module AbideDevUtils
  module Jira
    class ClientBuilder
      def initialize(config, **options)
        @options = options
        @config = config
      end

      def username
        find_option_value(:username)
      end

      def username=(username)
        @options[:username] = username
      end

      def password
        if find_option_value(:password)
          '********'
        else
          nil
        end
      end

      def password=(password)
        @options[:password] = password
      end

      def site
        find_option_value(:site)
      end

      def site=(site)
        @options[:site] = site
      end

      def context_path
        find_option_value(:context_path, default: '')
      end

      def context_path=(context_path)
        @options[:context_path] = context_path
      end

      def auth_type
        find_option_value(:auth_type, default: :basic)
      end

      def auth_type=(auth_type)
        @options[:auth_type] = auth_type
      end

      def http_debug
        find_option_value(:http_debug, default: false)
      end

      def http_debug=(http_debug)
        @options[:http_debug] = http_debug
      end

      def build
        JIRA::Client.new({
          username: find_option_value(:username, prompt: true),
          password: find_option_value(:password, prompt: true),
          site: find_option_value(:site, prompt: 'Jira site URL'),
          context_path: find_option_value(:context_path, default: ''),
          auth_type: find_option_value(:auth_type, default: :basic),
          http_debug: find_option_value(:http_debug, default: false),
        })
      end

      private

      def find_option_value(key, default: nil, prompt: nil)
        if prompt
          find_option_value_or_prompt(key, prompt)
        else
          find_option_value_or_default(key, default)
        end
      end

      def find_option_val(key)
        @options[key] || @config[key] || ENV["JIRA_#{key.to_s.upcase}"]
      end

      def find_option_value_or_prompt(key, prompt = 'Enter value')
        case key
        when /password/i
          find_option_val(key) || AbideDevUtils::Prompt.password
        when /username/i
          find_option_val(key) || AbideDevUtils::Prompt.username
        else
          find_option_val(key) || AbideDevUtils::Prompt.single_line(prompt)
        end
      end

      def find_option_value_or_default(key, default)
        find_option_val(key) || default
      end
    end
  end
end
