# frozen_string_literal: true

require 'spec_helper'
require 'abide_dev_utils/xccdf/diff/benchmark'
require 'pry'

RSpec.describe AbideDevUtils::XCCDF::Diff::BenchmarkDiff do
  let(:file_path1) { test_xccdf_files.find { |f| f.end_with?('v1.0.0-xccdf.xml') } }
  let(:file_path2) { test_xccdf_files.find { |f| f.end_with?('v1.1.0-xccdf.xml') } }

  describe '#new' do
    it 'creates new BenchmarkDiff instance' do
      described_class.new(file_path1, file_path2).is_a?(described_class)
    end
  end

  describe '#number_title_diff' do
    let(:benchmark_diff) { described_class.new(file_path1, file_path2) }
    let(:number_title_diff) { benchmark_diff.number_title_diff }

    it 'returns the correct number of changes' do
      binding.pry
      expect(number_title_diff.length).to eq(4)
    end

    it 'returns the correct change type for first change' do
      expect(number_title_diff[0][:type]).to eq(%i[number added])
    end

    it 'returns the correct change type for second change' do
      expect(number_title_diff[1][:type]).to eq(%i[number added])
    end
  end
end
