# frozen_string_literal: true

require 'jira-ruby'
require 'abide_dev_utils/output'
require 'abide_dev_utils/prompt'
require 'abide_dev_utils/config'
require 'abide_dev_utils/errors/jira'

module AbideDevUtils
  module Jira
    ERRORS = AbideDevUtils::Errors::Jira
    COV_PARENT_SUMMARY_PREFIX = '::BENCHMARK:: '
    COV_CHILD_SUMMARY_PREFIX = '::CONTROL:: '

    def self.project(client, project)
      client.Project.find(project)
    end

    def self.issue(client, issue)
      client.Issue.find(issue)
    end

    def self.myself(client)
      client.User.myself
    end

    def self.issuetype(client, id)
      client.Issuetype.find(id)
    end

    def self.priority(client, id)
      client.Priority.find(id)
    end

    def self.all_project_issues_attrs(project)
      raw_issues = project.issues
      raw_issues.collect(&:attrs)
    end

    def self.new_issue(client, project, summary, dry_run: false)
      if dry_run
        sleep(0.2)
        return Dummy.new
      end
      fields = {}
      fields['summary'] = summary
      fields['project'] = project(client, project)
      fields['reporter'] = myself(client)
      fields['issuetype'] = issuetype(client, '3')
      fields['priority'] = priority(client, '6')
      issue = client.Issue.build
      raise ERRORS::CreateIssueError, issue.attrs unless issue.save({ 'fields' => fields })

      issue
    end

    # This should probably be threaded in the future
    def self.bulk_new_issue(client, project, summaries, dry_run: false)
      summaries.each { |s| new_issue(client, project, s, dry_run: dry_run) }
    end

    def self.new_subtask(client, issue, summary, dry_run: false)
      if dry_run
        sleep(0.2)
        return Dummy.new
      end
      issue_fields = issue.attrs['fields']
      fields = {}
      fields['parent'] = issue
      fields['summary'] = summary
      fields['project'] = issue_fields['project']
      fields['reporter'] = myself(client)
      fields['issuetype'] = issuetype(client, '5')
      fields['priority'] = issue_fields['priority']
      subtask = client.Issue.build
      raise ERRORS::CreateSubtaskError, subtask.attrs unless subtask.save({ 'fields' => fields })

      subtask
    end

    def self.bulk_new_subtask(client, issue, summaries, dry_run: false)
      summaries.each do |s|
        new_subtask(client, issue, s, dry_run: dry_run)
      end
    end

    def self.client(options: {})
      opts = merge_options(options)
      opts[:username] = AbideDevUtils::Prompt.username if opts[:username].nil?
      opts[:password] = AbideDevUtils::Prompt.password if opts[:password].nil?
      opts[:site] = AbideDevUtils::Prompt.single_line('Jira URL') if opts[:site].nil?
      opts[:context_path] = '' if opts[:context_path].nil?
      opts[:auth_type] = :basic if opts[:auth_type].nil?
      JIRA::Client.new(opts)
    end

    def self.client_from_prompts(http_debug: false)
      options = {}
      options[:username] = AbideDevUtils::Prompt.username
      options[:password] = AbideDevUtils::Prompt.password
      options[:site] = AbideDevUtils::Prompt.single_line('Jira URL')
      options[:context_path] = ''
      options[:auth_type] = :basic
      options[:http_debug] = http_debug
      JIRA::Client.new(options)
    end

    def self.project_from_prompts(http_debug: false)
      client = client_from_prompts(http_debug)
      project = AbideDevUtils::Prompt.single_line('Project').upcase
      client.Project.find(project)
    end

    def self.new_issues_from_coverage(client, project, report, dry_run: false)
      dr_prefix = dry_run ? 'DRY RUN: ' : ''
      i_attrs = all_project_issues_attrs(project)
      rep_sums = summaries_from_coverage_report(report)
      rep_sums.each do |k, v|
        next if summary_exist?(k, i_attrs)

        parent = new_issue(client, project.attrs['key'], k.to_s, dry_run: dry_run)
        AbideDevUtils::Output.simple("#{dr_prefix}Created parent issue #{k}")
        parent_issue = issue(client, parent.attrs['key']) unless parent.respond_to?(:dummy)
        AbideDevUtils::Output.simple("#{dr_prefix}Creating subtasks, this can take a while...")
        progress = AbideDevUtils::Output.progress(title: "#{dr_prefix}Creating Subtasks", total: nil)
        v.each do |s|
          next if summary_exist?(s, i_attrs)

          progress.title = "#{dr_prefix}#{s}"
          new_subtask(client, parent_issue, s, dry_run: dry_run)
          progress.increment
        end
      end
    end

    def self.merge_options(options)
      config.merge(options)
    end

    def self.config
      AbideDevUtils::Config.config_section(:jira)
    end

    def self.summary_exist?(summary, issue_attrs)
      issue_attrs.each do |i|
        return true if i['fields']['summary'] == summary
      end
      false
    end

    def self.summaries_from_coverage_report(report)
      summaries = {}
      benchmark = nil
      report.each do |k, v|
        benchmark = v if k == 'benchmark'
        next unless k.match?(/^profile_/)

        parent_sum = k
        v.each do |sk, sv|
          next unless sk == 'uncovered'

          summaries[parent_sum] = sv.collect { |s| "#{COV_CHILD_SUMMARY_PREFIX}#{s}" }
        end
      end
      summaries.transform_keys { |k| "#{COV_PARENT_SUMMARY_PREFIX}#{benchmark}-#{k}"}
    end

    class Dummy
      def attrs
        { 'fields' => {
          'project' => 'dummy',
          'priority' => 'dummy'
        } }
      end

      def dummy
        true
      end
    end
  end
end
