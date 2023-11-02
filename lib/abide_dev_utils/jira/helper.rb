# frozen_string_literal: true

require_relative 'dry_run'

module AbideDevUtils
  module Jira
    class Helper
      extend DryRun

      dry_run_simple :add_issue_label
      dry_run_return_false :summary_exist?

      def initialize(client, dry_run: false)
        @client = client
        @dry_run = dry_run
      end

      # @param project [JIRA::Resource::Project, String]
      def all_project_issues_attrs(project)
        project = @client.find(:project, project)
        project.issues.collect(&:attrs)
      end

      # @param issue [JIRA::Resource::Issue, String]
      # @param label [String]
      def add_issue_label(issue, label)
        issue = @client.find(:issue, issue)
        return if issue.labels.include?(label)

        issue.labels << label
        issue.save
      end

      # @param summary [String]
      # @param issue_attrs [Array<Hash>]
      def summary_exist?(summary, issue_attrs)
        issue_attrs.any? { |attrs| attrs['fields'].key?('summary') && attrs['fields']['summary'] == summary }
      end
    end
  end
end
