# frozen_string_literal: true

require 'jira-ruby'
require 'abide_dev_utils/output'
require 'abide_dev_utils/prompt'
require 'abide_dev_utils/config'
require 'abide_dev_utils/errors/jira'
require_relative 'jira/client'

module AbideDevUtils
  module Jira
    ERRORS = AbideDevUtils::Errors::Jira
    COV_PARENT_SUMMARY_PREFIX = '::BENCHMARK:: '
    COV_CHILD_SUMMARY_PREFIX = '::CONTROL:: '
    UPD_EPIC_SUMMARY_PREFIX = '::BENCHMARK UPDATE::'
    PROGRESS_BAR_FORMAT = '%a %e %P% Created: %c of %C'

    def self.client(memo: true, dry_run: false, **options)
      return AbideDevUtils::Jira::Client.new(dry_run: dry_run, **options) unless memo

      @client ||= AbideDevUtils::Jira::Client.new(dry_run: dry_run, **options)
    end

    def self.new_issues_from_coverage(client, project, report, dry_run: false)
      dr_prefix = dry_run ? 'DRY RUN: ' : ''
      client(dry_run: dry_run) # Initializes the client if needed
      i_attrs = client.helper.all_project_issues_attrs(project)
      rep_sums = summaries_from_coverage_report(report)
      rep_sums.each do |k, v|
        next if client.helper.summary_exist?(k, i_attrs)

        AbideDevUtils::Output.simple("#{dr_prefix}Creating parent issue #{k}...")
        parent = client.create(:issue, project: project, summary: k.to_s)
        AbideDevUtils::Output.simple("#{dr_prefix}Creating subtasks, this can take a while...")
        progress = AbideDevUtils::Output.progress(title: "#{dr_prefix}Creating Subtasks", total: nil)
        v.each do |s|
          next if client.helper.summary_exist?(s, i_attrs)

          progress.title = "#{dr_prefix}#{s}"
          client.create(:subtask, parent: parent, summary: s)
          progress.increment
        end
      end
    end

    ToCreateData = Struct.new(:summary, :labels, :should_create, :metadata)

    def self.new_issues_from_xccdf(project, xccdf_path, epic: nil, dry_run: false, explain: false, label_include: nil)
      client(dry_run: dry_run) # Initializes the client if needed
      i_attrs = client.helper.all_project_issues_attrs(project)
      xccdf = AbideDevUtils::XCCDF::Benchmark.new(xccdf_path)
      # We need to get the actual epic Issue object, or create it if it doesn't exist
      epic = if epic.nil?
               new_epic_summary = "#{COV_PARENT_SUMMARY_PREFIX}#{xccdf.title}"
               if client.helper.summary_exist?(new_epic_summary, i_attrs)
                 client.find(:issue, new_epic_summary)
               else
                 unless AbideDevUtils::Prompt.yes_no("#{dr_prefix(dry_run)}Create new epic '#{new_epic_summary}'?")
                   AbideDevUtils::Output.simple("#{dr_prefix(dry_run)}Aborting")
                   exit(0)
                 end
                 client.create(:issue, project: project, summary: new_epic_summary, issuetype: 'Epic', epic_name: new_epic_summary)
               end
             else
               client.find(:issue, epic)
             end
      # Now we need to find out which issues we need to create for the benchmark
      # The profiles that the control belongs to will be added as an issue label
      to_create = []
      summaries_from_xccdf(xccdf).each do |profile_summary, control_summaries|
        control_summaries.each do |control_summary|
          existing_to_create = to_create.find { |tc| tc.summary == control_summary }
          if existing_to_create
            existing_to_create.labels << profile_summary.split.join('_').downcase
          else
            new_to_create = ToCreateData.new(
              summary: control_summary,
              labels: [profile_summary.split.join('_').downcase],
              should_create: true,
              metadata: {
                epic_key: epic.key,
                project: project,
              },
            )
            to_create << new_to_create
          end
        end
      end

      final_to_create = filter_to_create(to_create, label_include, project, epic)

      return explain_this(to_create) if explain

      unless AbideDevUtils::Prompt.yes_no("#{dr_prefix(dry_run)}Create #{final_to_create.count} new Jira issues?")
        AbideDevUtils::Output.simple("#{dr_prefix(dry_run)}Aborting")
        exit(0)
      end

      progress = AbideDevUtils::Output.progress(title: "#{dr_prefix(dry_run)}Creating issues",
                                                total: final_to_create.count,
                                                format: PROGRESS_BAR_FORMAT)
      final_to_create.each do |tc|
        abrev = tc.summary.length > 40 ? tc.summary[0..60] : tc.summary
        progress.log("#{dr_prefix(dry_run)}Creating #{abrev}...")
        client.create(:issue, project: project, summary: tc.summary, labels: tc.labels, epic_link: epic)
        progress.increment
      end
      progress.finish
      AbideDevUtils::Output.simple("#{dr_prefix(dry_run)}Done creating tasks in Epic '#{epic.summary}'")
    end

    def self.filter_to_create(to_create, label_include, project, epic)
      not_already_exists = filter_already_exists(to_create, project, epic)
      AbideDevUtils::Output.simple(
        "Filtered out #{to_create.count - not_already_exists.count} issues that already existed",
      )
      only_label_include = filter_label_include(not_already_exists, label_include)
      AbideDevUtils::Output.simple(
        "Filtered out #{not_already_exists.count - only_label_include.count} issues that didn't include the label #{label_include}",
      )
      only_label_include
    end

    def self.filter_already_exists(to_create, project, epic)
      AbideDevUtils::Output.simple('Checking if issues already exist...')
      project = client.find(:project, project)
      epic = client.find(:issue, epic)
      issues = client.find(:issues_by_jql, "project = \"#{project.key}\" AND 'Epic Link' = \"#{epic.key}\"")
      to_create.reject do |tc|
        if issues.any? { |i| i.summary == tc.summary }
          tc.metadata[:already_exists] = true
          tc.should_create = false
          true
        else
          tc.metadata[:already_exists] = false
          false
        end
      end
    end

    # If we have a label_include, we need to filter out any controls that don't have that label
    def self.filter_label_include(to_create, label_include)
      return to_create if label_include.nil?

      AbideDevUtils::Output.simple("Filtering out controls that don't match label include: #{label_include}")
      to_create.select do |tc|
        if tc.labels.any? { |l| l.match?(label_include) }
          tc.metadata[:label_include] = true
          true
        else
          tc.metadata[:label_include] = false
          tc.should_create = false
          false
        end
      end
    end

    def self.explain_this(to_create)
      should_create = to_create.select(&:should_create)
      should_not_create = to_create.reject(&:should_create)
      AbideDevUtils::Output.simple(AbideDevUtils::Output.simple_section_separator('EXPLAIN'))
      AbideDevUtils::Output.simple("Will create #{should_create.count} issues")
      AbideDevUtils::Output.simple("Will not create #{should_not_create.count} issues")
      AbideDevUtils::Output.simple(AbideDevUtils::Output.simple_section_separator('WILL CREATE'))
      should_create.each do |tc|
        AbideDevUtils::Output.simple("\"#{tc.summary}\"; labels: #{tc.labels}; metadata: #{tc.metadata}")
      end
      AbideDevUtils::Output.simple(AbideDevUtils::Output.simple_section_separator('WILL NOT CREATE'))
      should_not_create.each do |tc|
        AbideDevUtils::Output.simple("\"#{tc.summary}\"; labels: #{tc.labels}; metadata: #{tc.metadata}")
      end
      exit(0)
    end

    def self.new_issues_from_xccdf_diff(project, xccdf1_path, xccdf2_path, epic: nil, dry_run: false, auto_approve: false, diff_opts: {})
      require 'abide_dev_utils/xccdf/diff'
      diff = AbideDevUtils::XCCDF::Diff::BenchmarkDiff.new(xccdf1_path, xccdf2_path, diff_opts)
      client(dry_run: dry_run) # Initializes the client if needed
      i_attrs = client.helper.all_project_issues_attrs(project)
      # We need to get the actual epic Issue object, or create it if it doesn't exist
      epic = if epic.nil?
               new_epic_summary = "#{COV_PARENT_SUMMARY_PREFIX}#{xccdf.title}"
               if client.helper.summary_exist?(new_epic_summary, i_attrs)
                 client.find(:issue, new_epic_summary)
               else
                 unless AbideDevUtils::Prompt.yes_no("#{dr_prefix(dry_run)}Create new epic '#{new_epic_summary}'?")
                   AbideDevUtils::Output.simple("#{dr_prefix(dry_run)}Aborting")
                   exit(0)
                 end
                 client.create(:issue, project: project, summary: new_epic_summary, issuetype: 'Epic', epic_name: new_epic_summary)
               end
             else
               client.find(:issue, epic)
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
        client.create(:issue, project: project, summary: summary, description: description, labels: [], epic_link: epic)
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
