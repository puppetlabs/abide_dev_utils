# frozen_string_literal: true

require 'pathname'
require 'yaml'
require 'abide_dev_utils/xccdf'
require 'abide_dev_utils/errors'
require 'spec_helper'

spec_dir = Pathname.new(__dir__).parent
linux_xccdf = "#{spec_dir}/resources/cis/CIS_CentOS_Linux_7_Benchmark_v3.0.0-xccdf.xml"
windows_xccdf = "#{spec_dir}/resources/cis/CIS_Microsoft_Windows_Server_2016_RTM_\(Release_1607\)_Benchmark_v1.2.0-xccdf.xml"

benchmark_hash = {
  'Linux' => {
    benchmark: nil,
    title: 'CIS CentOS Linux 7 Benchmark',
    normalized_title: 'cis_centos_linux_7_benchmark',
    ctrl_full: 'xccdf_org.cisecurity.benchmarks_rule_1.1.1.3_Ensure_mounting_of_udf_filesystems_is_disabled',
    ctrl_name_fmt: 'ensure_mounting_of_udf_filesystems_is_disabled',
    ctrl_num_fmt: 'c1_1_1_3'
  },
  'Windows' => {
    benchmark: nil,
    title: 'CIS Microsoft Windows Server 2016 RTM (Release 1607) Benchmark',
    normalized_title: 'cis_microsoft_windows_server_2016_rtm_release_1607_benchmark',
    ctrl_full: 'xccdf_org.cisecurity.benchmarks_rule_1.1.3_L1_Ensure_Minimum_password_age_is_set_to_1_or_more_days',
    ctrl_name_fmt: 'ensure_minimum_password_age_is_set_to_1_or_more_days',
    ctrl_num_fmt: 'c1_1_3'
  }
}

RSpec.describe 'AbideDevUtils::XCCDF' do
  it 'creates a Benchmark object from Linux XCCDF' do
    expect { AbideDevUtils::XCCDF::Benchmark.new(linux_xccdf) }.not_to raise_error
  end

  it 'creates a Benchmark object from Windows XCCDF' do
    expect { AbideDevUtils::XCCDF::Benchmark.new(windows_xccdf) }.not_to raise_error
  end

  it 'Creates control map from Windows XCCDF' do
    opts = { console: true, type: 'cis', parent_key_prefix: '' }
    expect { AbideDevUtils::XCCDF.gen_map(windows_xccdf, opts)}.not_to raise_error
  end

  it 'Creates control map from Linux XCCDF' do
    opts = { console: true, type: 'cis', parent_key_prefix: '' }
    expect { AbideDevUtils::XCCDF.gen_map(linux_xccdf, opts)}.not_to raise_error
  end

  it 'raises FileNotFoundError when creating object Benchmark object with bad file path' do
    expect { AbideDevUtils::XCCDF::Benchmark.new('/fake/path') }.to raise_error(
      AbideDevUtils::Errors::FileNotFoundError
    )
  end

  context 'when using Benchmark object' do
    benchmark_hash['Linux'][:benchmark] = AbideDevUtils::XCCDF::Benchmark.new(linux_xccdf)
    benchmark_hash['Windows'][:benchmark] = AbideDevUtils::XCCDF::Benchmark.new(windows_xccdf)
    benchmark_hash.each do |os, data|
      context "from #{os} XCCDF" do
        let(:benchmark) { data[:benchmark] }
        let(:title) { data[:title] }
        let(:normalized_title) { data[:normalized_title] }
        let(:ctrl_full) { data[:ctrl_full] }
        let(:ctrl_name_fmt) { data[:ctrl_name_fmt] }
        let(:ctrl_num_fmt) { data[:ctrl_num_fmt] }

        it 'has correct title' do
          expect(benchmark.title).to eq(title)
        end

        it 'has correct normalized title' do
          expect(benchmark.normalized_title).to eq(normalized_title)
        end

        it 'returns and empty array on bad xpath query' do
          expect(benchmark.xpath('fake/xpath').empty?).to eq true
        end

        it 'correctly trims non-alphanumeric character at end of string' do
          expect(benchmark.normalize_string('test_string.')).to eq 'test_string'
        end

        it 'correctly trims non-alpha character at start of string' do
          expect(benchmark.normalize_string('.test_string')).to eq 'test_string'
        end

        it 'correctly trims level 1 prefix at start of string' do
          expect(benchmark.normalize_string('l1_test_string')).to eq 'test_string'
        end

        it 'correctly trims level 2 prefix at start of string' do
          expect(benchmark.normalize_string('l2_test_string')).to eq 'test_string'
        end

        it 'correctly normalizes string' do
          expect(benchmark.normalize_string('.l2_test_string.')).to eq 'test_string'
        end

        it 'correctly formats control name by name' do
          expect(benchmark.normalize_control_name(ctrl_full, number_format: false)).to eq ctrl_name_fmt
        end

        it 'correctly formats control name by num' do
          expect(benchmark.normalize_control_name(ctrl_full, number_format: true)).to eq ctrl_num_fmt
        end

        it "correctly creates #{os} parent key" do
          expect(YAML.safe_load(benchmark.to_hiera).key?("#{normalized_title}::title")).to be_truthy
        end
      end
    end
  end
end
