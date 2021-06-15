# frozen_string_literal: true

require 'json'
require 'abide_dev_utils/config'
require 'abide_dev_utils/jira'

module Abide
  module CLI
    CONFIG = AbideDevUtils::Config
    JIRA = AbideDevUtils::Jira

    class JiraCommand < CmdParse::Command
      CMD_NAME = 'jira'
      CMD_SHORT = 'Commands related to Jira tickets'
      CMD_LONG = 'Namespace for commands related to Jira tickets'
      def initialize
        super(CMD_NAME, takes_commands: true)
        short_desc(CMD_SHORT)
        long_desc(CMD_LONG)
        add_command(CmdParse::HelpCommand.new, default: true)
        add_command(JiraAuthCommand.new)
        add_command(JiraGetIssueCommand.new)
        add_command(JiraNewIssueCommand.new)
        add_command(JiraFromCoverageCommand.new)
      end
    end

    class JiraAuthCommand < CmdParse::Command
      CMD_NAME = 'auth'
      CMD_SHORT = 'Test authentication with Jira'
      CMD_LONG = 'Allows you to test authenticating with Jira'
      def initialize
        super(CMD_NAME, takes_commands: false)
        short_desc(CMD_SHORT)
        long_desc(CMD_LONG)
      end

      def execute
        client = JIRA.client
        myself = JIRA.get_myself(client)
        return if myself.attrs['name'].empty?

        Abide::CLI::OUTPUT.simple("Successfully authenticated user #{myself.attrs['name']}!")
      end
    end

    class JiraGetIssueCommand < CmdParse::Command
      CMD_NAME = 'get_issue'
      CMD_SHORT = 'Gets a specific issue'
      CMD_LONG = 'Returns JSON of a specific issue from key (<project>-<num>)'
      def initialize
        super(CMD_NAME, takes_commands: false)
        short_desc(CMD_SHORT)
        long_desc(CMD_LONG)
        argument_desc(ISSUE: 'A Jira issue key (<PROJECT>-<NUM>)')
        options.on('-o [FILE]', '--out-file [FILE]', 'Path to save the JSON output') { |o| @data[:file] = o }
      end

      def execute(issue)
        client = JIRA.client(options: {})
        issue = client.Issue.find(issue)
        console = @data[:file].nil?
        out_json = issue.attrs.select { |_, v| !v.nil? || !v.empty? }
        Abide::CLI::OUTPUT.json(out_json, console: console, file: @data[:file])
      end
    end

    class JiraNewIssueCommand < CmdParse::Command
      CMD_NAME = 'new_issue'
      CMD_SHORT = 'Creates a new issue in a project'
      CMD_LONG = 'Allows you to create a new issue in a project'
      def initialize
        super(CMD_NAME, takes_commands: false)
        short_desc(CMD_SHORT)
        long_desc(CMD_LONG)
        argument_desc(
          PROJECT: 'Jira project name (should be all caps)',
          SUMMARY: 'Brief summary of the issue',
          SUBTASKS: 'One or more summaries that become subtasks'
        )
      end

      def execute(project, summary, *subtasks)
        client = JIRA.client(options: {})
        issue = JIRA.new_issue(client, project, summary)
        Abide::CLI::OUTPUT.simple("Successfully created #{issue.attrs['key']}")
        return if subtasks.nil? || subtasks.empty?

        Abide::CLI::OUTPUT.simple('Creatings subtasks...')
        JIRA.bulk_new_subtask(client, JIRA.issue(client, issue.attrs['key']), subtasks) unless subtasks.empty?
      end
    end

    class JiraFromCoverageCommand < CmdParse::Command
      CMD_NAME = 'from_coverage'
      CMD_SHORT = 'Creates a parent issue with subtasks from a coverage report'
      CMD_LONG = 'Creates a parent issue with subtasks for a benchmark and any uncovered controls'
      def initialize
        super(CMD_NAME, takes_commands: false)
        short_desc(CMD_SHORT)
        long_desc(CMD_LONG)
        argument_desc(REPORT: 'A JSON coverage report from the abide puppet coverage command', PROJECT: 'A Jira project')
        options.on('-d', '--dry-run', 'Print to console instead of saving objects') { |_| @data[:dry_run] = true }
      end

      def execute(report, project)
        Abide::CLI::VALIDATE.file(report)
        @data[:dry_run] = false if @data[:dry_run].nil?
        client = JIRA.client(options: {})
        proj = JIRA.project(client, project)
        File.open(report) do |f|
          JIRA.new_issues_from_coverage(client, proj, JSON.parse(f.read), dry_run: @data[:dry_run])
        end
      end
    end
  end
end
