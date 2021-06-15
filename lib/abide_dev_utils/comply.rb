# frozen_string_literal: true

require 'yaml'
require 'selenium-webdriver'
require 'abide_dev_utils/output'

module AbideDevUtils
  module Comply
    def self.scan_report(url, password, username: 'comply', status: nil, ignorelist: nil, onlylist: nil)
      begin
        AbideDevUtils::Output.simple 'Starting headless Chrome...'
        options = Selenium::WebDriver::Chrome::Options.new
        options.args = %w[
          --headless
          --test-type
          --disable-gpu
          --no-first-run
          --no-default-browser-check
          --ignore-certificate-errors
          --start-maximized
        ]
        driver = Selenium::WebDriver.for :chrome, options: options
        driver.get(url)
        bypass_ssl_warning_page(driver)
        AbideDevUtils::Output.simple "Logging into Comply at #{url}..."
        login_to_comply(driver, username: username, password: password)
        AbideDevUtils::Output.simple 'Finding nodes with scan reports...'
        links = find_node_report_links(driver)
        AbideDevUtils::Output.simple 'Building scan reports, this may take a while...'
        build_report(driver, links, status: status, ignorelist: ignorelist, onlylist: onlylist)
      ensure
        driver.quit
      end
    end

    def self.ignore_no_such_element
      begin
        yield
      rescue Selenium::WebDriver::Error::NoSuchElementError => e
        AbideDevUtils::Output.simple "Ignored exception #{e}", stream: $stderr
      end
    end

    def self.wait_on(timeout = 10)
      Selenium::WebDriver::Wait.new(timeout: timeout).until do
        yield
      end
    end

    def self.bypass_ssl_warning_page(driver)
      ignore_no_such_element do
        driver.find_element(id: 'details-button').click
        driver.find_element(id: 'proceed-link').click
      end
    end

    def self.login_to_comply(driver, username: 'comply', password: 'compliance')
      wait_on { driver.find_element(id: 'username') }
      driver.find_element(id: 'username').send_keys username
      driver.find_element(id: 'password').send_keys password
      driver.find_element(id: 'kc-login').click
    end

    def self.find_node_report_links(driver)
      wait_on { driver.find_element(class: 'metric-containers-failed-hosts-count') }
      hosts = driver.find_element(class: 'metric-containers-failed-hosts-count')
      table = hosts.find_element(class: 'rc-table')
      table_body = table.find_element(tag_name: 'tbody')
      wait_on { table_body.find_element(tag_name: 'a') }
      table_body.find_elements(tag_name: 'a')
    end

    def self.build_report(driver, links, status: nil, ignorelist: nil, onlylist: nil)
      all_checks = {}
      original_window = driver.window_handle
      links.each do |link|
        if !onlylist.nil? && !onlylist.empty?
          next unless onlylist.include?(link.text)
        elsif !ignorelist.nil? && !ignorelist.empty?
          next if ignorelist.include?(link.text)
        end
        begin
          node_name = link.text
          progress = AbideDevUtils::Output.progress title: "Builingd report for #{node_name}", total: nil
          link_url = link.attribute('href')
          driver.manage.new_window(:tab)
          wait_on { driver.window_handles.length == 2 }
          progress.increment
          driver.switch_to.window driver.window_handles[1]
          driver.get(link_url)
          wait_on { driver.find_element(class: 'details-scan-info') }
          progress.increment
          wait_on { driver.find_element(class: 'details-table') }
          progress.increment
          report = {}
          report['scan_results'] = {}
          scan_info_table = driver.find_element(class: 'details-scan-info')
          scan_info_table_rows = scan_info_table.find_elements(tag_name: 'tr')
          progress.increment
          check_table_body = driver.find_element(tag_name: 'tbody')
          check_table_rows = check_table_body.find_elements(tag_name: 'tr')
          progress.increment
          scan_info_table_rows.each do |row|
            key = row.find_element(tag_name: 'h5').text
            value = row.find_element(tag_name: 'strong').text
            report[key.downcase.gsub(/:/, '').gsub(/ /, '_')] = value
            progress.increment
          end
          check_table_rows.each do |row|
            chk_objs = row.find_elements(tag_name: 'td')
            chk_objs.map!(&:text)
            if status.nil? || status.include?(chk_objs[1].downcase)
              report['scan_results'][chk_objs[0][/^[0-9.]+/, 0]] = {
                'name' => chk_objs[0].gsub(/\n/, ' '),
                'status' => chk_objs[1]
              }
            end
            progress.increment
          end
          all_checks[node_name] = report
          driver.close
          AbideDevUtils::Output.simple "Created report for #{node_name}"
        ensure
          driver.switch_to.window original_window
        end
      end
      all_checks
    end
  end
end
