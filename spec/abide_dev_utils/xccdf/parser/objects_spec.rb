# frozen_string_literal: true

require 'spec_helper'
require 'abide_dev_utils/xccdf/parser'
require 'abide_dev_utils/xccdf/parser/objects'
require 'pry'

RSpec.describe AbideDevUtils::XCCDF::Parser::Objects do
  let(:file_path) { test_xccdf_files.find { |f| f.end_with?('v1.0.0-xccdf.xml') } }
  let(:benchmark) { AbideDevUtils::XCCDF::Parser.parse(file_path) }

  describe AbideDevUtils::XCCDF::Parser::Objects::Benchmark do
    describe 'class methods' do
      describe '#xpath' do
        it 'returns the xpath to the benchmark' do
          expect(described_class.xpath).to eq('xccdf:Benchmark')
        end
      end
    end

    describe 'instance methods' do
      describe '#to_s' do
        it 'returns a string representation of the benchmark' do
          expect(benchmark.to_s).to eq('Test XCCDF 1.0.0')
        end
      end

      describe '#version' do
        it 'returns the benchmark version' do
          expect(benchmark.version.to_s).to eq('1.0.0')
        end
      end

      describe '#title' do
        it 'returns the benchmark title' do
          expect(benchmark.title.to_s).to eq('Test XCCDF')
        end
      end

      describe '#group' do
        it 'returns the correct number of groups' do
          expect(benchmark.group.count).to eq(2)
        end
      end

      describe '#value' do
        it 'returns the correct number of values' do
          expect(benchmark.value.count).to eq(6)
        end
      end

      describe 'profile' do
        it 'returns correct amount' do
          expect(benchmark.profile.count).to eq(2)
        end

        it 'returns profile objects with correct titles' do
          expect(benchmark.profile.map { |p| p.title.to_s }).to satisfy('correct titles included') do |t|
            t.include?('Level 1 (L1) - Profile 1') && t.include?('Level 2 (L2) - Profile 2')
          end
        end

        it 'returns profile objects with correct levels' do
          expect(benchmark.profile.map(&:level)).to satisfy('correct levels included') do |l|
            l.include?('Level 1') && l.include?('Level 2')
          end
        end
      end
    end
  end
end
