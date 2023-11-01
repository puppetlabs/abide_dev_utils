# frozen_string_literal: true

require_relative '../errors/jira'

module AbideDevUtils
  module Jira
    class Finder
      def initialize(client)
        @client = client
      end

      def myself
        client.User.myself
      end

      # @param id [String] The project key or ID
      def project(id)
        return id if id.is_a?(client.Project.target_class)

        client.Project.find(id)
      end

      # @param id [String] The issue key  or summary
      def issue(id)
        return id if id.is_a?(client.Issue.target_class)

        client.Issue.find(id)
      rescue URI::InvalidURIError
        iss = client.Issue.all.find { |i| i.summary == id }
        raise AbideDevUtils::Errors::Jira::FindIssueError, id if iss.nil?

        iss
      end

      # @param id [String] The issuetype ID or name
      def issuetype(id)
        return id if id.is_a?(client.Issuetype.target_class)

        if id.match?(%r{^\d+$})
          client.Issuetype.find(id)
        else
          client.Issuetype.all.find { |i| i.name == id }
        end
      end

      # @param id [String] The priority ID or name
      def priority(id)
        return id if id.is_a?(client.Priority.target_class)

        if id.match?(%r{^\d+$})
          client.Priority.find(id)
        else
          client.Priority.all.find { |i| i.name == id }
        end
      end

      private

      attr_reader :client
    end
  end
end
