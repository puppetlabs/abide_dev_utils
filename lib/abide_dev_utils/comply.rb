# frozen_string_literal: true

require 'json'
require 'yaml'
require 'selenium-webdriver'
require 'abide_dev_utils/errors/comply'
require 'abide_dev_utils/gcloud'
require 'abide_dev_utils/output'
require 'abide_dev_utils/prompt'
require 'pry'

module AbideDevUtils
  # Holds module methods and a class for dealing with Puppet Comply
  module Comply
    include AbideDevUtils::Errors::Comply

    def self.build_report(url, password, config = nil, **opts)
      ReportScraper.new(url, config, **opts).build_report(password)
    end

    def self.compare_reports(report_a, report_b, **opts)
      report_name = opts.fetch(:report_name, nil)
      current_report = ScanReport.new.from_yaml(report_a)
      last_report = if opts.fetch(:remote_storage, '') == 'gcloud'
                      report_name = report_b if report_name.nil?
                      ScanReport.new.from_yaml(ScanReport.fetch_report(name: report_b))
                    else
                      report_name = File.basename(report_b) if report_name.nil?
                      ScanReport.new.from_yaml(File.read(report_b))
                    end
      result, details = current_report.report_comparison(last_report, check_goodness: true)
      if result
        AbideDevUtils::Output.simple('No negative differences detected...')
        AbideDevUtils::Output.simple(JSON.pretty_generate(details))
      else
        AbideDevUtils::Output.simple('Negative differences detected!', stream: $stderr)
        AbideDevUtils::Output.simple(JSON.pretty_generate(details), stream: $stderr)
      end
      if opts.fetch(:upload, false) && !opts.fetch(:remote_storage, '').empty? && !report_name.nil?
        AbideDevUtils::Output.simple('Uploading current report...')
        ScanReport.upload_report(File.expand_path(report_a), name: report_name)
        AbideDevUtils::Output.simple('Successfully uploaded report.')
      end
      result
    end

    # Class that uses Selenium WebDriver to gather scan reports from Puppet Comply
    class ReportScraper
      attr_reader :timeout,
                  :username,
                  :status,
                  :ignorelist,
                  :onlylist,
                  :max_pagination,
                  :screenshot_on_error,
                  :page_source_on_error

      def initialize(url, config = nil, **opts)
        @url = url
        @config = config
        @opts = opts
        @timeout = fetch_option(:timeout, 10).to_i
        @username = fetch_option(:username, 'comply')
        @status = fetch_option(:status)
        @ignorelist = fetch_option(:ignorelist, [])
        @onlylist = fetch_option(:onlylist, [])
        @max_pagination = fetch_option(:max_pagination, 5).to_i
        @screenshot_on_error = fetch_option(:screenshot_on_error, false)
        @page_source_on_error = fetch_option(:page_source_on_error, false)
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
                                     --no-sandbox
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

      def find_elements(subject = driver, **kwargs)
        driver.manage.window.resize_to(1920, 1080)
        subject.find_elements(**kwargs)
      end

      def wait_on(timeout: @timeout,
                  ignore_nse: false,
                  quit_driver: true,
                  quiet: false,
                  ignore: [Selenium::WebDriver::Error::NoSuchElementError],
                  &block)
        raise 'wait_on must be passed a block' unless block

        value = nil
        if ignore_nse
          begin
            Selenium::WebDriver::Wait.new(ignore: [], timeout: timeout, interval: 1).until do
              value = yield
            end
          rescue Selenium::WebDriver::Error::NoSuchElementError
            return value
          rescue StandardError => e
            raise_error(e, AbideDevUtils::Comply::WaitOnError, quit_driver: quit_driver, quiet: quiet)
          end
        else
          begin
            Selenium::WebDriver::Wait.new(ignore: ignore, timeout: timeout, interval: 1).until do
              value = yield
            end
          rescue StandardError => e
            raise_error(e, AbideDevUtils::Comply::WaitOnError, quit_driver: quit_driver, quiet: quiet)
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

      def raise_error(original, err_class = nil, quit_driver: true, quiet: false)
        output.simple 'Something went wrong!' unless quiet
        if screenshot_on_error
          output.simple 'Taking a screenshot of current page state...' unless quiet
          screenshot
        end

        if page_source_on_error
          output.simple 'Saving page source of current page...' unless quiet
          page_source
        end

        driver.quit if quit_driver
        actual_err_class = err_class.nil? ? original.class : err_class
        raise actual_err_class, original.message
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

        raise AbideDevUtils::Comply::ComplyLoginFailedError, error_text
      end

      def filter_node_report_links(node_report_links)
        if onlylist.empty? && ignorelist.empty?
          output.simple 'No filters set, using all node reports...'
          return node_report_links
        end

        unless onlylist.empty?
          output.simple 'Onlylist found, filtering node reports...'
          return node_report_links.select { |l| onlylist.include?(l[:name]) }
        end

        output.simple 'Ignorelist found, filtering node reports...'
        node_report_links.reject { |l| ignorelist.include?(l[:name]) }
      end

      def find_node_report_table(subject)
        wait_on { find_element(subject, class: 'metric-containers-failed-hosts-count') }
        hosts = find_element(subject, class: 'metric-containers-failed-hosts-count')
        table = find_element(hosts, class: 'rc-table')
        wait_on { find_element(table, tag_name: 'tbody') }
        find_element(table, tag_name: 'tbody')
      end

      def wait_for_node_report_links(table_body)
        wait_on(timeout: 2, quit_driver: false, quiet: true) { table_body.find_element(tag_name: 'a') }
        output.simple 'Found node report links...'
        table_body.find_elements(tag_name: 'a')
      rescue AbideDevUtils::Comply::WaitOnError
        []
      end

      def find_node_report_links
        output.simple 'Finding nodes with scan reports...'
        node_report_links = []
        (1..max_pagination).each do |page|
          output.simple "Trying page #{page}..."
          driver.get("#{@url}/dashboard?page=#{page}&limit=50")
          table_body = find_node_report_table(driver)
          elems = wait_for_node_report_links(table_body)
          if elems.empty?
            output.simple "No links found on page #{page}, stopping search..."
            break
          end

          elems.each do |elem|
            node_report_links << { name: elem.text, url: elem.attribute('href') }
          end
        end
        driver.get(@url)
        filter_node_report_links(node_report_links)
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

      def wait_on_element_and_increment(subject = driver, **element_id)
        element = wait_on { find_element(subject, **element_id) }
        progress.increment
        element
      end

      def wait_on_elements_and_increment(subject = driver, **element_id)
        elements = wait_on { find_elements(subject, **element_id) }
        progress.increment
        elements
      end

      def scrape_report
        output.simple 'Building scan reports, this may take a while...'
        all_checks = {}
        original_window = driver.window_handle
        node_report_links.each do |link|
          node_name = link[:name]
          link_url = link[:url]
          new_progress(node_name)
          driver.manage.new_window(:tab)
          progress.increment
          wait_on { driver.window_handles.length == 2 }
          progress.increment
          driver.switch_to.window driver.window_handles[1]
          driver.get(link_url)
          wait_on_element_and_increment(class: 'details-header')
          wait_on_element_and_increment(class: 'details-scan-info')
          wait_on_element_and_increment(class: 'details-table')
          report = { 'scan_results' => {} }
          scan_info_table = wait_on_element_and_increment(class: 'details-scan-info')
          scan_info_table_rows = wait_on_elements_and_increment(scan_info_table, tag_name: 'tr')
          check_table_body = wait_on_element_and_increment(tag_name: 'tbody')
          check_table_rows = wait_on_elements_and_increment(check_table_body, tag_name: 'tr')
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
        rescue ::StandardError => e
          raise_error(e)
        ensure
          driver.switch_to.window original_window
        end
        all_checks
      end
    end

    # Contains multiple NodeScanReport objects
    class ScanReport
      attr_reader :node_scan_reports

      def from_yaml(report)
        @scan_report = if report.is_a? Hash
                         report
                       elsif File.file?(report)
                         File.open(report.to_s, 'r') { |f| YAML.safe_load(f.read) }
                       else
                         YAML.safe_load(report)
                       end
        @node_scan_reports = build_node_scan_reports
        self
      end

      def to_h
        node_scan_reports.each_with_object({}) do |node, h|
          h[node.name] = node.hash
        end
      end

      def to_yaml
        to_h.to_yaml
      end

      def self.storage_bucket
        @storage_bucket ||= AbideDevUtils::GCloud.storage_bucket
      end

      def self.fetch_report(name: 'comply_report.yaml')
        report = storage_bucket.file(name)
        report.download.read
      end

      def self.upload_report(report, name: 'comply_report.yaml')
        storage_bucket.create_file(report, name)
      end

      def report_comparison(other, check_goodness: false)
        comparison = []
        node_scan_reports.zip(other.node_scan_reports).each do |cr, lr|
          comparison << { cr.name => { diff: {}, node_presense: :new } } if lr.nil?
          comparison << { lr.name => { diff: {}, node_presense: :dropped } } if cr.nil?
          comparison << { cr.name => { diff: cr.diff(lr), node_presence: :same } } unless cr.nil? || lr.nil?
        end
        comparison.inject(&:merge)
        return good_comparison?(comparison) if check_goodness

        compairison
      end

      def good_comparison?(report_comparison)
        good = true
        not_good = {}
        report_comparison.each do |node_report|
          node_name = node_report.keys[0]
          report = node_report[node_name]
          next if report[:diff].empty?

          not_good[node_name] = {}
          unless report.dig(:diff, :passing, :other).nil?
            good = false
            not_good[node_name][:new_not_passing] = report[:diff][:passing][:other]
          end
          unless report.dig(:diff, :failing, :self).nil?
            good = false
            not_good[node_name][:new_failing] = report[:diff][:failing][:self]
          end
        end
        [good, not_good]
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
      attr_reader :name, :passing, :failing, :error, :not_checked, :informational, :benchmark, :last_scan, :profile

      DIFF_PROPERTIES = %i[passing failing error not_checked informational].freeze

      def initialize(node_name, node_hash)
        @name = node_name
        @hash = node_hash
        @passing = node_hash.dig('scan_results', 'Pass') || {}
        @failing = node_hash.dig('scan_results', 'Fail') || {}
        @error = node_hash.dig('scan_results', 'Error') || {}
        @not_checked = node_hash.dig('scan_results', 'Not checked') || {}
        @informational = node_hash.dig('scan_results', 'Informational') || {}
        @benchmark = node_hash['benchmark']
        @last_scan = node_hash['last_scan']
        @profile = node_hash.fetch('custom_profile', nil) || node_hash.fetch('profile', nil)
        create_equality_methods
      end

      def diff(other)
        diff = {}
        DIFF_PROPERTIES.each do |prop|
          diff[prop] = send("#{prop.to_s}_equal?".to_sym, other.send(prop)) ? {} : property_diff(prop, other)
        end
        diff
      end

      private

      def create_equality_methods
        DIFF_PROPERTIES.each do |prop|
          meth_name = "#{prop.to_s}_equal?"
          self.class.define_method(meth_name) do |other|
            property_equal?(prop, other)
          end
        end
      end

      def property_diff(property, other)
        {
          self: send(property).keys - other.send(property).keys,
          other: other.send(property).keys - send(property).keys
        }
      end

      def property_equal?(property, other_property)
        send(property) == other_property
      end
    end
  end
end
