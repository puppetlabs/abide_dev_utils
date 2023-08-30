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
    UPD_EPIC_SUMMARY_PREFIX = '::BENCHMARK UPDATE::'
    PROGRESS_BAR_FORMAT = '%a %e %P% Created: %c of %C'

    def self.project(client, project)
      client.Project.find(project)
    end

    def self.issue(client, issue)
      client.Issue.find(issue)
    rescue URI::InvalidURIError
      iss = client.Issue.all.find { |i| i.summary == issue }
      raise ERRORS::FindIssueError, issue unless iss

      iss
    end

    def self.myself(client)
      client.User.myself
    end

    def self.issuetype(client, id)
      if id.match?(%r{^\d+$})
        client.Issuetype.find(id)
      else
        client.Issuetype.all.find { |i| i.name == id }
      end
    end

    def self.priority(client, id)
      if id.match?(%r{^\d+$})
        client.Priority.find(id)
      else
        client.Priority.all.find { |i| i.name == id }
      end
    end

    def self.all_project_issues_attrs(project)
      raw_issues = project.issues
      raw_issues.collect(&:attrs)
    end

    def self.add_issue_label(iss, label, dry_run: false)
      return if dry_run || iss.labels.include?(label)

      iss.labels << profile_summary
      iss.save
    end

    def self.new_issue(client, project, summary, description: nil, labels: ['abide_dev_utils'], epic: nil, dry_run: false)
      if dry_run
        sleep(0.2)
        return Dummy.new(summary)
      end
      fields = {}
      fields['summary'] = summary
      fields['project'] = project(client, project)
      fields['issuetype'] = issuetype(client, 'Task')
      fields['priority'] = priority(client, '3')
      fields['description'] = description if description
      fields['labels'] = labels
      epic = issue(client, epic) if epic && !epic.is_a?(JIRA::Resource::Issue)
      fields['customfield_10006'] = epic.key if epic # Epic_Link
      iss = client.Issue.build
      raise ERRORS::CreateIssueError, iss.attrs unless iss.save({ 'fields' => fields })

      iss
    end

    def self.new_epic(client, project, summary, dry_run: false)
      AbideDevUtils::Output.simple("#{dr_prefix(dry_run)}Creating epic '#{summary}'")
      if dry_run
        sleep(0.2)
        return Dummy.new(summary)
      end
      fields = {
        'summary' => summary,
        'project' => project(client, project),
        'issuetype' => issuetype(client, 'Epic'),
        'customfield_10007' => summary, # Epic Name
      }
      iss = client.Issue.build
      raise ERRORS::CreateEpicError, iss.attrs unless iss.save({ 'fields' => fields })

      iss
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
      return client_from_prompts if opts.empty?

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

    def self.new_issues_from_xccdf(client, project, xccdf_path, epic: nil, dry_run: false)
      i_attrs = all_project_issues_attrs(project)
      xccdf = AbideDevUtils::XCCDF::Benchmark.new(xccdf_path)
      # We need to get the actual epic Issue object, or create it if it doesn't exist
      epic = if epic.nil?
               new_epic_summary = "#{COV_PARENT_SUMMARY_PREFIX}#{xccdf.title}"
               if summary_exist?(new_epic_summary, i_attrs)
                 issue(client, new_epic_summary)
               else
                 unless AbideDevUtils::Prompt.yes_no("#{dr_prefix(dry_run)}Create new epic '#{new_epic_summary}'?")
                   AbideDevUtils::Output.simple("#{dr_prefix(dry_run)}Aborting")
                   exit(0)
                 end
                 new_epic(client, project.key, new_epic_summary, dry_run: dry_run)
               end
             else
               issue(client, epic)
             end
      # Now we need to find out which issues we need to create for the benchmark
      # The profiles that the control belongs to will be added as an issue label
      to_create = {}
      summaries_from_xccdf(xccdf).each do |profile_summary, control_summaries|
        control_summaries.reject { |s| summary_exist?(s, i_attrs) }.each do |control_summary|
          if to_create.key?(control_summary)
            to_create[control_summary] << profile_summary.split.join('_').downcase
          else
            to_create[control_summary] = [profile_summary.split.join('_').downcase]
          end
        end
      end

      unless AbideDevUtils::Prompt.yes_no("#{dr_prefix(dry_run)}Create #{to_create.keys.count} new Jira issues?")
        AbideDevUtils::Output.simple("#{dr_prefix(dry_run)}Aborting")
        exit(0)
      end

      progress = AbideDevUtils::Output.progress(title: "#{dr_prefix(dry_run)}Creating issues",
                                                total: to_create.keys.count,
                                                format: PROGRESS_BAR_FORMAT)
      to_create.each do |control_summary, labels|
        abrev = control_summary.length > 40 ? control_summary[0..60] : control_summary
        progress.log("#{dr_prefix(dry_run)}Creating #{abrev}...")
        new_issue(client, project.key, control_summary, labels: labels, epic: epic, dry_run: dry_run)
        progress.increment
      end
      progress.finish
      AbideDevUtils::Output.simple("#{dr_prefix(dry_run)}Done creating tasks in Epic '#{epic.summary}'")
    end

    def self.new_issues_from_xccdf_diff(client, project, xccdf1_path, xccdf2_path, epic: nil, dry_run: false, auto_approve: false, diff_opts: {})
      require 'abide_dev_utils/xccdf/diff'
      diff = AbideDevUtils::XCCDF::Diff::BenchmarkDiff.new(xccdf1_path, xccdf2_path, diff_opts)
      i_attrs = all_project_issues_attrs(project)
      # We need to get the actual epic Issue object, or create it if it doesn't exist
      epic = if epic.nil?
               new_epic_summary = "#{UPD_EPIC_SUMMARY_PREFIX}#{diff.this.title}: v#{diff.this.version} -> #{diff.other.version}"
               if summary_exist?(new_epic_summary, i_attrs)
                 issue(client, new_epic_summary)
               else
                 unless AbideDevUtils::Prompt.yes_no("#{dr_prefix(dry_run)}Create new epic '#{new_epic_summary}'?", auto_approve: auto_approve)
                   AbideDevUtils::Output.simple("#{dr_prefix(dry_run)}Aborting")
                   exit(0)
                 end
                 new_epic(client, project.key, new_epic_summary, dry_run: dry_run)
               end
             else
               issue(client, epic)
             end
      to_create = {}
      diff.diff[:rules].each do |key, val|
        next if val.empty?

        val.each do |v|
          case key
          when :added
            sum = "Add rule #{v[:number]} - #{v[:title]}"
            sum = "#{sum[0..60]}..." if sum.length > 60
            to_create[sum] = <<~DESC
              Rule #{v[:number]} - #{v[:title]} is added with #{diff.other.title} #{diff.other.version}
            DESC
          when :removed
            sum = "Remove rule #{v[:number]} - #{v[:title]}"
            sum = "#{sum[0..60]}..." if sum.length > 60
            to_create[sum] = <<~DESC
              Rule #{v[:number]} - #{v[:title]} is removed from #{diff.this.title} #{diff.this.version}
            DESC
          else
            sum = "Update rule \"#{v[:from]}\""
            sum = "#{sum[0..60]}..." if sum.length > 60
            to_create[sum] = <<~DESC
              Rule #{v[:from]} is updated in #{diff.other.title} #{diff.other.version}:
              #{v[:changes].collect { |k, v| "#{k}: #{v}" }.join("\n")}
            DESC
          end
        end
      end
      approved_create = {}
      to_create.each do |summary, description|
        if AbideDevUtils::Prompt.yes_no("#{dr_prefix(dry_run)}Create new issue '#{summary}' with description:\n#{description}", auto_approve: auto_approve)
          approved_create[summary] = description
        end
      end
      AbideDevUtils::Output.simple("#{dr_prefix(dry_run)}Creating #{approved_create.keys.count} new Jira issues")
      progress = AbideDevUtils::Output.progress(title: "#{dr_prefix(dry_run)}Creating issues",
                                                total: approved_create.keys.count,
                                                format: PROGRESS_BAR_FORMAT)
      approved_create.each do |summary, description|
        progress.log("#{dr_prefix(dry_run)}Creating #{summary}...")
        new_issue(client, project.key, summary, description: description, labels: [], epic: epic, dry_run: dry_run)
        progress.increment
      end
      progress.finish
      AbideDevUtils::Output.simple("#{dr_prefix(dry_run)}Done creating tasks in Epic '#{epic.summary}'")
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

    def self.summaries_from_coverage_report(report) # rubocop:disable Metrics/CyclomaticComplexity
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

    def self.summaries_from_xccdf(xccdf)
      summaries = {}
      xccdf.profiles.each do |profile|
        sum_key = "#{profile.level}_#{profile.title}".split.join('_').downcase
        summaries[sum_key] = profile.controls.collect do |control|
          control_id = control.respond_to?(:vulnid) ? control.vulnid : control.number
          summary = "#{control_id} - #{control.title}"
          summary = "#{summary[0..251]}..." if summary.length > 255
          summary
        end
      end
      summaries
    end

    def self.dr_prefix(dry_run)
      dry_run ? 'DRY RUN: ' : ''
    end

    class Dummy
      attr_reader :summary, :key

      def initialize(summary = 'dummy summary')
        @summary = summary
        @key = 'DUM-111'
      end

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
