# frozen_string_literal: true

require 'spec_helper'
require 'abide_dev_utils/ppt'
require 'abide_dev_utils/cem/benchmark'

RSpec.describe('AbideDevUtils::CEM::Benchmark') do
  { cem_linux: cem_linux_fixture, cem_windows: cem_windows_fixture }.each do |mname, fix|
    context "with #{mname}" do
      around do |example|
        Dir.chdir(fix) do
          @pupmod = AbideDevUtils::Ppt::PuppetModule.new
          @benchmarks = AbideDevUtils::CEM::Benchmark.benchmarks_from_puppet_module(@pupmod)
          example.run
        end
      end

      context 'when supplied a PuppetModule' do
        it 'creates benchmark objects correctly' do
          expect(@benchmarks.empty?).not_to be_truthy
        end

        it 'creates the correct number of objects' do
          expect(@benchmarks.length).to eq @pupmod.supported_os.length
        end

        it 'creates objects with resource data' do
          expect(@benchmarks.all? { |b| !b.resource_data.nil? && !b.resource_data.empty? }).to be_truthy
        end

        it 'creates objects with mapping data' do
          expect(@benchmarks.all? { |b| !b.map_data.nil? && !b.map_data.empty? }).to be_truthy
        end

        it 'creates objects with title' do
          expect(@benchmarks.all? { |b| b.title.is_a?(String) && !b.title.empty? }).to be_truthy
        end

        it 'creates objects with version' do
          expect(@benchmarks.all? { |b| b.version.is_a?(String) && !b.version.empty? }).to be_truthy
        end

        it 'creates objects with title key' do
          expect(@benchmarks.all? { |b| b.title_key.is_a?(String) && !b.title_key.empty? }).to be_truthy
        end

        it 'creates objects with rules' do
          expect(@benchmarks.all? { |b| b.rules.is_a?(Hash) && !b.rules.empty? }).to be_truthy
        end
      end
    end
  end
end
