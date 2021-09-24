# frozen_string_literal: true

require 'yaml'
require 'selenium-webdriver'
require 'abide_dev_utils/errors/comply'
require 'abide_dev_utils/gcloud'
require 'abide_dev_utils/output'
require 'abide_dev_utils/prompt'

module AbideDevUtils
  # Holds module methods and a class for dealing with Puppet Comply
  module Comply
    include AbideDevUtils::Errors::Comply

    def self.build_report(url, password, config = nil, **opts)
      ReportScraper.new(url, config, **opts).build_report(password)
    end

    def self.check_for_regressions(url, password, config = nil, **opts)
      current_report = build_report(url, password, config, **opts)
      last_report = if opts.fetch(:remote_report_storage, '') == 'gcloud'
                      fetch_report
                    else
                      File.open(opts[:last_report], 'r', &:read)
                    end
      result, details = good_comparison?(report_comparison(current_report, last_report))
      if result
        puts 'A-OK'
      else
        puts 'Uh-Oh'
        puts details
      end
    end

    # Class that uses Selenium WebDriver to gather scan reports from Puppet Comply
    class ReportScraper
      def initialize(url, config = nil, **opts)
        @url = url
        @config = config
        @opts = opts
      end

      def timeout
        @timeout ||= fetch_option(:timeout, 10).to_i
      end

      def username
        @username ||= fetch_option(:username, 'comply')
      end

      def status
        @status ||= fetch_option(:status)
      end

      def ignorelist
        @ignorelist ||= fetch_option(:ignorelist, [])
      end

      def onlylist
        @onlylist ||= fetch_option(:onlylist, [])
      end

      def screenshot_on_error
        @screenshot_on_error ||= fetch_option(:screenshot_on_error, true)
      end

      def page_source_on_error
        @page_source_on_error ||= fetch_option(:page_source_on_error, true)
      end

      def build_report(password)
        connect(password)
        scrape_report
      ensure
        driver.quit
      end

      def file_dir
        @file_dir ||= File.expand_path('~/abide_dev_utils')
      end

      def file_dir=(path)
        @file_dir = new_file_dir(path)
      end

      private

      attr_reader :progress

      def fetch_option(option, default = nil)
        return @opts.fetch(option, default) if @config.nil?

        @opts.key?(option) ? @opts[option] : @config.fetch(option, default)
      end

      def node_report_links
        @node_report_links ||= find_node_report_links
      end

      def driver
        @driver ||= new_driver
      end

      def output
        AbideDevUtils::Output
      end

      def prompt
        AbideDevUtils::Prompt
      end

      def new_progress(node_name)
        @progress = AbideDevUtils::Output.progress title: "Building report for #{node_name}", total: nil
      end

      def new_driver
        options = Selenium::WebDriver::Chrome::Options.new
        options.args = @opts.fetch(:driveropts, %w[
                                     --headless
                                     --test-type
                                     --disable-gpu
                                     --no-first-run
                                     --no-default-browser-check
                                     --ignore-certificate-errors
                                     --start-maximized
                                   ])
        output.simple 'Starting headless Chrome...'
        Selenium::WebDriver.for(:chrome, options: options)
      end

      def find_element(subject = driver, **kwargs)
        driver.manage.window.resize_to(1920, 1080)
        subject.find_element(**kwargs)
      end

      def wait_on(ignore_nse: false, ignore: [Selenium::WebDriver::Error::NoSuchElementError], &block)
        raise 'wait_on must be passed a block' unless block

        value = nil
        if ignore_nse
          begin
            Selenium::WebDriver::Wait.new(ignore: [], timeout: timeout).until do
              value = yield
            end
          rescue Selenium::WebDriver::Error::NoSuchElementError
            return value
          rescue => e
            raise_error(e)
          end
        else
          begin
            Selenium::WebDriver::Wait.new(ignore: ignore, timeout: timeout).until do
              value = yield
            end
          rescue => e
            raise_error(e)
          end
        end
        value
      end

      def new_file_dir(path)
        return File.expand_path(path) if Dir.exist?(File.expand_path(path))

        create_dir = prompt.yes_no("Directory #{path} does not exist. Create directory?")
        return unless create_dir

        require 'fileutils'
        FileUtils.mkdir_p path
      end

      def raise_error(err)
        output.simple 'Something went wrong!'
        if screenshot_on_error
          output.simple 'Taking a screenshot of current page state...'
          screenshot
        end

        if page_source_on_error
          output.simple 'Saving page source of current page...'
          page_source
        end

        driver.quit
        raise err
      end

      def screenshot
        driver.save_screenshot(File.join(file_dir, "comply_error_#{Time.now.to_i}.png"))
      rescue Errno::ENOENT
        save_default = prompt.yes_no(
          "Directory #{file_dir} does not exist. Save screenshot to current directory?"
        )
        driver.save_screenshot(File.join(File.expand_path('.'), "comply_error_#{Time.now.to_i}.png")) if save_default
      end

      def page_source
        File.open(File.join(file_dir, "comply_error_#{Time.now.to_i}.txt"), 'w') { |f| f.write(driver.page_source) }
      rescue Errno::ENOENT
        save_default = prompt.yes_no(
          "Directory #{file_dir} does not exist. Save page source to current directory?"
        )
        if save_default
          File.open(File.join(File.expand_path('.'), "comply_error_#{Time.now.to_i}.html"), 'w') do |f|
            f.write(driver.page_source)
          end
        end
      end

      def bypass_ssl_warning_page
        wait_on(ignore_nse: true) do
          find_element(id: 'details-button').click
          find_element(id: 'proceed-link').click
        end
      end

      def login_to_comply(password)
        output.simple "Logging into Comply at #{@url}..."
        wait_on { driver.find_element(id: 'username') }
        find_element(id: 'username').send_keys username
        find_element(id: 'password').send_keys password
        find_element(id: 'kc-login').click
        error_text = wait_on(ignore_nse: true) { find_element(class: 'kc-feedback-text').text }
        return if error_text.nil? || error_text.empty?

        raise ComplyLoginFailedError, error_text
      end

      def find_node_report_links
        output.simple 'Finding nodes with scan reports...'
        hosts = wait_on { find_element(class: 'metric-containers-failed-hosts-count') }
        table = find_element(hosts, class: 'rc-table')
        table_body = find_element(table, tag_name: 'tbody')
        wait_on { table_body.find_elements(tag_name: 'a') }
      end

      def connect(password)
        output.simple "Connecting to #{@url}..."
        driver.get(@url)
        bypass_ssl_warning_page
        login_to_comply(password)
      end

      def normalize_cis_rec_name(name)
        nstr = name.downcase
        nstr.delete!('(/|\\|\+|:|\'|")')
        nstr.gsub!(/(\s|\(|\)|-|\.)/, '_')
        nstr.strip!
        nstr
      end

      def scrape_report
        output.simple 'Building scan reports, this may take a while...'
        all_checks = {}
        original_window = driver.window_handle
        if !onlylist.empty?
          node_report_links.reject! { |l| !onlylist.include?(l.text) }
        elsif !ignorelist.empty?
          node_report_links.reject! { |l| ignorelist.include?(l.text) }
        end
        node_report_links.each do |link|
          begin
            node_name = link.text
            new_progress(node_name)
            link_url = link.attribute('href')
            driver.manage.new_window(:tab)
            progress.increment
            wait_on { driver.window_handles.length == 2 }
            progress.increment
            driver.switch_to.window driver.window_handles[1]
            driver.get(link_url)
            wait_on { find_element(class: 'details-scan-info') }
            progress.increment
            wait_on { find_element(class: 'details-table') }
            progress.increment
            report = { 'scan_results' => {} }
            scan_info_table = find_element(class: 'details-scan-info')
            scan_info_table_rows = scan_info_table.find_elements(tag_name: 'tr')
            progress.increment
            check_table_body = find_element(tag_name: 'tbody')
            check_table_rows = check_table_body.find_elements(tag_name: 'tr')
            progress.increment
            scan_info_table_rows.each do |row|
              key = find_element(row, tag_name: 'h5').text
              value = find_element(row, tag_name: 'strong').text
              report[key.downcase.tr(':', '').tr(' ', '_')] = value
              progress.increment
            end
            check_table_rows.each do |row|
              chk_objs = row.find_elements(tag_name: 'td')
              chk_objs.map!(&:text)
              if status.nil? || status.include?(chk_objs[1].downcase)
                name_parts = chk_objs[0].match(/^([0-9.]+) (.+)$/)
                key = normalize_cis_rec_name(name_parts[2])
                unless report['scan_results'].key?(chk_objs[1])
                  report['scan_results'][chk_objs[1]] = {}
                end
                report['scan_results'][chk_objs[1]][key] = {
                  'name' => name_parts[2].chomp,
                  'number' => name_parts[1].chomp
                }
              end
              progress.increment
            end
            all_checks[node_name] = report
            driver.close
            output.simple "Created report for #{node_name}"
          rescue => e
            raise_error(e)
          ensure
            driver.switch_to.window original_window
          end
        end
        all_checks
      end
    end

    # Contains multiple NodeScanReport objects
    class ScanReport
      def from_yaml(report)
        @scan_report = if report.is_a? Hash
                         report
                       elsif File.file?(report)
                         File.open(report.to_s, 'r') { |f| YAML.safe_load(f.read) }
                       else
                         YAML.safe_load(report)
                       end
        build_node_scan_reports
      end

      private

      def build_node_scan_reports
        node_scan_reports = []
        @scan_report.each do |node_name, node_hash|
          node_scan_reports << NodeScanReport.new(node_name, node_hash)
        end
        node_scan_reports.sort_by(&:name)
      end
    end

    # Class representation of a Comply node scan report
    class NodeScanReport
      attr_reader :name, :passing, :failing, :not_checked, :informational, :benchmark, :last_scan, :profile

      DIFF_PROPERTIES = %i[passing failing not_checked informational].freeze

      def initialize(node_name, node_hash)
        @name = node_name
        @hash = node_hash
        @passing = node_hash.dig('scan_results', 'Pass') || {}
        @failing = node_hash.dig('scan_results', 'Fail') || {}
        @not_checked = node_hash.dig('scan_results', 'Not checked') || {}
        @informational = node_hash.dig('scan_results', 'Informational') || {}
        @benchmark = node_hash['benchmark']
        @last_scan = node_hash['last_scan']
        @profile = node_hash.fetch('custom_profile', nil) || node_hash.fetch('profile', nil)
      end

      def diff(other)
        diff = {}
        DIFF_PROPERTIES.each do |prop|
          diff[prop] = send("#{prop.to_s}_equal?".to_sym, other.send(prop)) ? {} : property_diff(prop, other)
        end
        diff
      end

      def method_missing(method_name, *args, &_block)
        case method_name
        when method_name.match?(/^(passing|failing|not_checked|informational)_equal?$/)
          property_equal?(method_name.delete_suffix('_equal?'), *args)
        when method_name.match?(/^(to_h|to_yaml)$/)
          @hash.send(method_name.to_sym)
        end
      end

      def respond_to_missing?(method_name, _include_private = false)
        method_name.match?(/^(((passing|failing|not_checked|informational)_equal?)|to_h|to_yaml)$/)
      end

      private

      def property_diff(property, other)
        {
          self: send(property).keys - other.send(property).keys,
          other: other.send(property).keys - send(property).keys
        }
      end

      def property_equal?(property, other_property)
        send(property.to_sym) == other_property
      end
    end

    def self.storage_bucket
      @storage_bucket ||= AbideDevUtils::GCloud.storage_bucket
    end

    def self.fetch_report
      report = storage_bucket.file('comply_report.yaml')
      report.download.read
    end

    def self.upload_report(report)
      file_to_upload = report.is_a?(Hash) ? report.to_yaml : report
      storage_bucket.create_file(file_to_upload, 'comply_report.yaml')
    end

    def self.report_comparison(current, last)
      current_report = ScanReport.new.from_yaml(current)
      last_report = ScanReport.new.from_yaml(last)

      comparison = []
      current_report.zip(last_report).each do |cr, lr|
        comparison << { cr.name => { diff: {}, node_presense: :new } } if lr.nil?
        comparison << { lr.name => { diff: {}, node_presense: :dropped } } if cr.nil?
        comparison << { cr.name => { diff: cr.diff(lr), node_presence: :same } } unless cr.nil? || lr.nil?
      end
      comparison.inject(&:merge)
    end

    def self.good_comparison?(report_comparison)
      good = true
      not_good = {}
      report_comparison.each do |node_name, report|
        next if report[:diff].empty?

        not_good[node_name] = {}
        unless report[:diff][:passing][:other].empty?
          good = false
          not_good[node_name][:new_not_passing] = report[:diff][:passing][:other]
        end
        unless report[:diff][:failing][:self].empty?
          good = false
          not_good[node_name][:new_failing] = report[:diff][:failing][:self]
        end
      end
      [good, not_good]
    end
  end
end
