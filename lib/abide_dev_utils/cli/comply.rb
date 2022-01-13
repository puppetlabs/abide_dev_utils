# frozen_string_literal: true

require 'abide_dev_utils/comply'
require 'abide_dev_utils/cli/abstract'

module Abide
  module CLI
    class ComplyCommand < AbideCommand
      CMD_NAME = 'comply'
      CMD_SHORT = 'Commands related to Puppet Comply'
      CMD_LONG = 'Namespace for commands related to Puppet Comply'
      def initialize
        super(CMD_NAME, CMD_SHORT, CMD_LONG, takes_commands: true)
        add_command(ComplyReportCommand.new)
        add_command(ComplyCompareReportCommand.new)
      end
    end

    class ComplyReportCommand < AbideCommand
      CMD_NAME = 'report'
      CMD_SHORT = 'Generates a yaml report of Puppet Comply scan results'
      CMD_LONG = <<~LONGCMD
        Generates a yaml file that shows the scan results of all nodes in Puppet Comply.
        This command utilizes Selenium WebDriver and the Google Chrome browser to automate
        clicking through the Comply UI and building a report. In order to use this command,
        you MUST have Google Chrome installed and you MUST install the chromedriver binary.
        More info and instructions can be found here:
        https://www.selenium.dev/documentation/en/getting_started_with_webdriver/.
      LONGCMD
      CMD_COMPLY_URL = 'The URL (including https://) of Puppet Comply'
      CMD_COMPLY_PASSWORD = 'The password for Puppet Comply'
      OPT_TIMEOUT_DESC = <<~EOTO
        The number of seconds you would like requests to wait before timing out. Defaults
        to 10 seconds.
      EOTO
      OPT_STATUS_DESC = <<~EODESC
        A comma-separated list of check statuses to ONLY include in the report.
        Valid statuses are: pass, fail, error, notapplicable, notchecked, unknown, informational
      EODESC
      OPT_IGNORE_NODES = <<~EOIGN
        A comma-separated list of node certnames to ignore building reports for. This
        options is mutually exclusive with --only and, if both are set, --only will take precedence
        over this option.
      EOIGN
      OPT_ONLY_NODES = <<~EOONLY
        A comma-separated list of node certnames to ONLY build reports for. No other
        nodes will have reports built for them except the ones specified. This option
        is mutually exclusive with --ignore and, if both are set, this options will
        take precedence over --ignore.
      EOONLY
      def initialize
        super(CMD_NAME, CMD_SHORT, CMD_LONG, takes_commands: false)
        argument_desc(COMPLY_URL: CMD_COMPLY_URL, COMPLY_PASSWORD: CMD_COMPLY_PASSWORD)
        options.on('-o [FILE]', '--out-file [FILE]', 'Path to save the report') { |f| @data[:file] = f }
        options.on('-u [USERNAME]', '--username [USERNAME]', 'The username for Comply (defaults to comply)') do |u|
          @data[:username] = u
        end
        options.on('-t [SECONDS]', '--timeout [SECONDS]', OPT_TIMEOUT_DESC) do |t|
          @data[:timeout] = t
        end
        options.on('-s [X,Y,Z]', '--status [X,Y,Z]',
                   %w[pass fail error notapplicable notchecked unknown informational],
                   Array,
                   OPT_STATUS_DESC) do |s|
          s&.map! { |i| i == 'notchecked' ? 'not checked' : i }
          @data[:status] = s
        end
        options.on('--only [X,Y,Z]', Array, OPT_ONLY_NODES) do |o|
          @data[:onlylist] = o
        end
        options.on('--ignore [X,Y,Z]', Array, OPT_IGNORE_NODES) do |i|
          @data[:ignorelist] = i
        end
        options.on('--page-source-on-error', 'Dump page source to file on error') do
          @data[:page_source_on_error] = true
        end
      end

      def help_arguments
        <<~ARGHELP
          Arguments:
              COMPLY_URL        #{CMD_COMPLY_URL}
              COMPLY_PASSWORD   #{CMD_COMPLY_PASSWORD}

        ARGHELP
      end

      def execute(comply_url = nil, comply_password = nil)
        Abide::CLI::VALIDATE.filesystem_path(`command -v chromedriver`.strip)
        conf = config_section('comply')
        comply_url = conf.fetch(:url) if comply_url.nil?
        comply_password = comply_password.nil? ? conf.fetch(:password, Abide::CLI::PROMPT.password) : comply_password
        report = AbideDevUtils::Comply.build_report(comply_url, comply_password, conf, **@data)
        outfile = @data.fetch(:file, nil).nil? ? conf.fetch(:report_path, 'comply_scan_report.yaml') : @data[:file]
        Abide::CLI::OUTPUT.yaml(report, file: outfile)
      end
    end

    class ComplyCompareReportCommand < AbideCommand
      CMD_NAME = 'compare-report'
      CMD_SHORT = 'Compare two Comply reports and get the differences.'
      CMD_LONG = 'Compare two Comply reports and get the differences. Report A is compared to report B, showing what changes it would take for A to equal B.'
      CMD_REPORT_A = 'The current Comply report yaml file'
      CMD_REPORT_B = 'The old Comply report yaml file name or full path'
      def initialize
        super(CMD_NAME, CMD_SHORT, CMD_LONG, takes_commands: false)
        argument_desc(REPORT_A: CMD_REPORT_A, REPORT_B: CMD_REPORT_B)
        options.on('-u', '--upload-new', 'If you want to upload the new scan report') { @data[:upload] = true }
        options.on('-s [STORAGE]', '--remote-storage [STORAGE]', 'Remote storage to upload the report to. (Only supports "gcloud")') { |x| @data[:remote_storage] = x }
        options.on('-r [NAME]', '--name [NAME]', 'The name to upload the report as') { |x| @data[:report_name] = x }
      end

      def execute(report_a, report_b)
        AbideDevUtils::Comply.compare_reports(report_a, report_b, @data)
      end
    end
  end
end
