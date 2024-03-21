# frozen_string_literal: true

# require 'abide_dev_utils/xccdf/parser'
require 'spec_helper'

RSpec.describe AbideDevUtils::XCCDF::Parser do
  describe '#parse' do
    it 'parses a valid XCCDF file' do
      file_path = test_xccdf_files.first
      benchmark = described_class.parse(file_path)
      benchmark.is_a?(AbideDevUtils::XCCDF::Parser::Objects::Benchmark)
    end
  end
end
