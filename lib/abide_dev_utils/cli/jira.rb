# frozen_string_literal: true

require 'json'
require 'abide_dev_utils/config'
require 'abide_dev_utils/jira'

module Abide
  module CLI
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
        add_command(JiraFromXccdfCommand.new)
        add_command(JiraFromXccdfDiffCommand.new)
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
        return if AbideDevUtils::Jira.client.myself.attrs['displayName'].empty?

        Abide::CLI::OUTPUT.simple("Successfully authenticated user #{AbideDevUtils::Jira.client.myself.attrs['displayName']}!")
      end
    end

    class JiraGetIssueCommand < CmdParse::Command
      CMD_NAME = 'get-issue'
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
        issue = AbideDevUtils::Jira.client.find(:issue, issue)
        console = @data[:file].nil?
        out_json = issue.attrs.select { |_, v| !v.nil? || !v.empty? }
        Abide::CLI::OUTPUT.json(out_json, console: console, file: @data[:file])
      end
    end

    class JiraNewIssueCommand < CmdParse::Command
      CMD_NAME = 'new-issue'
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
        issue = AbideDevUtils::Jira.client.create(:issue, project: project, summary: summary)
        Abide::CLI::OUTPUT.simple("Successfully created #{issue.attrs['key']}")
        return if subtasks.nil? || subtasks.empty?

        Abide::CLI::OUTPUT.simple('Creatings subtasks...')
        subtasks.each do |sum|
          subtask = AbideDevUtils::Jira.client.create(:subtask, parent: issue, summary: sum)
          Abide::CLI::OUTPUT.simple("Successfully created #{subtask.attrs['key']}")
        end
      end
    end

    class JiraFromCoverageCommand < CmdParse::Command
      CMD_NAME = 'from-coverage'
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
        File.open(report) do |f|
          AbideDevUtils::Jira.new_issues_from_coverage(project, JSON.parse(f.read), dry_run: @data[:dry_run])
        end
      end
    end

    class JiraFromXccdfCommand < CmdParse::Command
      CMD_NAME = 'from-xccdf'
      CMD_SHORT = 'Creates a parent issue with subtasks from a xccdf file'
      CMD_LONG = 'Creates a parent issue with subtasks for a benchmark and any uncovered controls'
      def initialize
        super(CMD_NAME, takes_commands: false)
        short_desc(CMD_SHORT)
        long_desc(CMD_LONG)
        argument_desc(PATH: 'An XCCDF file', PROJECT: 'A Jira project')
        options.on('-d', '--dry-run', 'Runs through mock issue creation. Useful for testing, but not reliable for knowing what exactly will be created. Use --explain for more accurate information.') do
          @data[:dry_run] = true
        end
        options.on('-x', '--explain', 'Shows a report of all the controls that will and won\'t be created as issues, and why. DOES NOT create issues.') do
          @data[:explain] = true
        end
        options.on('-e [EPIC]', '--epic [EPIC]', 'If given, tasks will be created and assigned to this epic. Takes form <PROJECT>-<NUM>') { |e| @data[:epic] = e }
        options.on('-l [LEVEL]', '--level [LEVEL]', 'Only create tasks for rules belonging to the matching level. Takes a string that is treated as RegExp') do |x|
          @data[:level] = x
        end
        options.on('-p [PROFILE]', '--profile [PROFILE]', 'Only create tasks for rules belonging to the matching profile. Takes a string that is treated as RegExp') do |x|
          @data[:profile] = x
        end
      end

      def execute(path, project)
        Abide::CLI::VALIDATE.file(path)
        # Each control gets assigned labels based on the levels and profiles it supports.
        # Those labels all take the form "level_<level>_<profile>". This allows us to
        # filter the controls we want to create tasks for by level and profile.
        @data[:label_include] = nil
        @data[:label_include] = "level_#{@data[:level]}_" if @data[:level]
        @data[:label_include] = "#{@data[:label_include]}#{@data[:profile]}" if @data[:profile]
        Abide::CLI::OUTPUT.simple "Label include: #{@data[:label_include]}"
        AbideDevUtils::Jira.new_issues_from_xccdf(
          project,
          path,
          epic: @data[:epic],
          dry_run: @data[:dry_run],
          explain: @data[:explain],
          label_include: @data[:label_include],
        )
      end
    end

    class JiraFromXccdfDiffCommand < CmdParse::Command
      CMD_NAME = 'from-xccdf-diff'
      CMD_SHORT = 'Creates an Epic with tasks from a xccdf diff'
      CMD_LONG = 'Creates an Epic with tasks for changes in a diff of two XCCDF files'
      def initialize
        super(CMD_NAME, takes_commands: false)
        short_desc(CMD_SHORT)
        long_desc(CMD_LONG)
        argument_desc(PATH1: 'An XCCDF file', PATH2: 'An XCCDF file', PROJECT: 'A Jira project')
        options.on('-d', '--dry-run', 'Print to console instead of saving objects') { |_| @data[:dry_run] = true }
        options.on('-y', '--yes', 'Automatically approve all yes / no prompts') { |_| @data[:auto_approve] = true }
        options.on('-e [EPIC]', '--epic [EPIC]', 'If given, tasks will be created and assigned to this epic. Takes form <PROJECT>-<NUM>') { |e| @data[:epic] = e }
        options.on('-p [PROFILE]', '--profile', 'Only diff rules belonging to the matching profile. Takes a string that is treated as RegExp') do |x|
          @data[:diff_opts] ||= {}
          @data[:diff_opts][:profile] = x
        end
        options.on('-l [LEVEL]', '--level', 'Only diff rules belonging to the matching level. Takes a string that is treated as RegExp') do |x|
          @data[:diff_opts] ||= {}
          @data[:diff_opts][:level] = x
        end
        options.on('-i [PROPS]', '--ignore-changed-properties', 'Ignore changes to specified properties. Takes a comma-separated list.') do |x|
          @data[:diff_opts] ||= {}
          @data[:diff_opts][:ignore_changed_properties] = x.split(',')
        end
      end

      def execute(path1, path2, project)
        Abide::CLI::VALIDATE.file(path1)
        Abide::CLI::VALIDATE.file(path2)
        AbideDevUtils::Jira.new_issues_from_xccdf_diff(
          project,
          path1,
          path2,
          epic: @data[:epic],
          dry_run: @data[:dry_run],
          auto_approve: @data[:auto_approve],
          diff_opts: @data[:diff_opts],
        )
      end
    end
  end
end
