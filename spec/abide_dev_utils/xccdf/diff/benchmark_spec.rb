# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AbideDevUtils::XCCDF::Diff::BenchmarkDiff do
  let(:file_path1) { test_xccdf_files.find { |f| f.end_with?('v1.0.0-xccdf.xml') } }
  let(:file_path2) { test_xccdf_files.find { |f| f.end_with?('v1.1.0-xccdf.xml') } }

  describe '#new' do
    it 'creates new BenchmarkDiff instance' do
      described_class.new(file_path1, file_path2).is_a?(described_class)
    end
  end
end
