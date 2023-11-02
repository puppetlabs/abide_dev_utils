# frozen_string_literal: true

require_relative 'client_builder'
require_relative 'dry_run'
require_relative 'finder'
require_relative 'helper'
require_relative 'issue_builder'
require_relative '../config'
require_relative '../errors/jira'

module AbideDevUtils
  module Jira
    class Client
      extend DryRun

      dry_run :create, :find, :myself

      attr_accessor :default_project
      attr_reader :config

      def initialize(dry_run: false, **options)
        @dry_run = dry_run
        @options = options
        @config = AbideDevUtils::Config.config_section('jira')
        @default_project = @config[:default_project]
        @client = nil
        @finder = nil
        @issue_builder = nil
        @helper = nil
      end

      def myself
        @myself ||= finder.myself
      end

      def find(type, id)
        raise ArgumentError, "Invalid type #{type}" unless finder.respond_to?(type.to_sym)

        finder.send(type.to_sym, id)
      end

      def create(type, **fields)
        issue_builder.create(type, **fields)
      end

      def helper
        @helper ||= Helper.new(self, dry_run: @dry_run)
      end

      private

      def client
        @client ||= ClientBuilder.new(@config, **@options).build
      end

      def finder
        @finder ||= Finder.new(client)
      end

      def issue_builder
        @issue_builder ||= IssueBuilder.new(client, finder)
      end
    end
  end
end
