# frozen_string_literal: true

require 'abide_dev_utils'
require 'abide_dev_utils/errors'

RSpec.describe 'AbideDevUtils::XCCDF::CIS::Hiera' do
  let(:hiera) do
    AbideDevUtils::XCCDF::CIS::Hiera.new('/Users/heston.snodgrass/Documents/CIS/benchmarks/CIS_CentOS_Linux_7_Benchmark_v3.0.0-xccdf.xml')
  end

  it 'creates a Hiera object from an XCCDF file' do
    expect(hiera).to exist
  end

  it 'raises FileNotFoundError when creating Hiera object with bad file path' do
    expect { AbideDevUtils::XCCDF::CIS::Hiera.new('/fake/path') }.to raise_error(AbideDevUtils::Errors::FileNotFoundError)
  end

  it 'passes respond_to? to doc attribute' do
    expect(hiera.respond_to?(:xpath)).to eq true
  end

  it 'passes respond_to? to hash attribute' do
    expect(hiera.respond_to?(:dig)).to eq true
  end

  it 'correctly responds to valid xpath query' do
    expect(hiera.xpath('xccdf:Benchmark/xccdf:title').children.to_s).to eq 'CIS CentOS Linux 7 Benchmark'
  end

  it 'returns and empty array on bad xpath query' do
    expect(hiera.xpath('fake/xpath').empty?).to eq true
  end

  it 'correctly returns value from hash attr using bracket syntax' do
    expect(hiera[:cis_centos_linux_7_benchmark][:version]).to eq '3.0.0'
  end
end
