# frozen_string_literal: true

require 'pathname'
require 'abide_dev_utils'
require 'abide_dev_utils/errors'

RSpec.describe 'AbideDevUtils::XCCDF::CIS::Hiera' do
  let(:xccdf_dir) { Pathname.new(__dir__).parent }
  let(:mod_spec_dir) { Pathname.new(xccdf_dir.to_s).parent }
  let(:spec_dir) { Pathname.new(mod_spec_dir.to_s).parent }
  let(:linux_xccdf) { "#{spec_dir}/resources/cis/CIS_CentOS_Linux_7_Benchmark_v3.0.0-xccdf.xml" }
  let(:windows_xccdf) { "#{spec_dir}/resources/cis/CIS_Microsoft_Windows_Server_2016_RTM_\(Release_1607\)_Benchmark_v1.2.0-xccdf.xml" }
  let(:cis_linux_hiera) { AbideDevUtils::XCCDF::CIS::Hiera.new(linux_xccdf) }
  let(:cis_windows_hiera) { AbideDevUtils::XCCDF::CIS::Hiera.new(windows_xccdf) }
  let(:ctrl) { 'xccdf_org.cisecurity.benchmarks_rule_1.1.1.3_Ensure_mounting_of_udf_filesystems_is_disabled' }
  let(:ctrl_name_fmt) { 'ensure_mounting_of_udf_filesystems_is_disabled' }
  let(:ctrl_num_fmt) { 'c1_1_1_3' }

  it 'creates a Hiera object from Linux XCCDF file' do
    expect(cis_linux_hiera).to exist
  end

  it 'creates a Hiera object from Windows XCCDF file' do
    expect(cis_windows_hiera).to exist
  end

  it 'raises FileNotFoundError when creating Hiera object with bad file path' do
    expect { AbideDevUtils::XCCDF::CIS::Hiera.new('/fake/path') }.to raise_error(AbideDevUtils::Errors::FileNotFoundError)
  end

  it 'passes respond_to? to doc attribute' do
    cis_linux_hiera.respond_to?(:xpath)
  end

  it 'passes respond_to? to hash attribute' do
    cis_linux_hiera.respond_to?(:dig)
  end

  it 'correctly responds to valid xpath query' do
    expect(cis_linux_hiera.xpath('xccdf:Benchmark/xccdf:title').children.to_s).to eq 'CIS CentOS Linux 7 Benchmark'
  end

  it 'returns and empty array on bad xpath query' do
    expect(cis_linux_hiera.xpath('fake/xpath').empty?).to eq true
  end

  it 'correctly returns value from hash attr using bracket syntax' do
    expect(cis_linux_hiera[:cis_centos_linux_7_benchmark][:version]).to eq '3.0.0'
  end

  it 'correctly trims non-alphanumeric character at end of string' do
    expect(cis_linux_hiera.send(:normalize_str, 'test_string.')).to eq 'test_string'
  end

  it 'correctly trims non-alpha character at start of string' do
    expect(cis_linux_hiera.send(:normalize_str, '.test_string')).to eq 'test_string'
  end

  it 'correctly trims level 1 prefix at start of string' do
    expect(cis_linux_hiera.send(:normalize_str, 'l1_test_string')).to eq 'test_string'
  end

  it 'correctly trims level 2 prefix at start of string' do
    expect(cis_linux_hiera.send(:normalize_str, 'l2_test_string')).to eq 'test_string'
  end

  it 'correctly normalizes string' do
    expect(cis_linux_hiera.send(:normalize_str, '.l2_test_string.')).to eq 'test_string'
  end

  it 'correctly formats control name by name' do
    expect(cis_linux_hiera.send(:normalize_ctrl_name, ctrl, false)).to eq ctrl_name_fmt
  end

  it 'correctly formats control name by num' do
    expect(cis_linux_hiera.send(:normalize_ctrl_name, ctrl, true)).to eq ctrl_num_fmt
  end

  it 'correctly creates Linux parent key' do
    cis_linux_hiera[:cis_centos_linux_7_benchmark].key?(:profile_level_1__server)
  end

  it 'correctly creates Windows parent key with ngws sub' do
    cis_windows_hiera[:cis_microsoft_windows_server_2016_rtm_release_1607_benchmark].key?(:profile_ngws___domain_controller)
  end
end
