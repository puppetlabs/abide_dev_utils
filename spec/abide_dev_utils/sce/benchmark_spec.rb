# frozen_string_literal: true

require 'spec_helper'
# require 'abide_dev_utils/ppt'
# require 'abide_dev_utils/sce/benchmark'

RSpec.describe('AbideDevUtils::Sce::Benchmark') do
  { sce_linux: sce_linux_fixture, sce_windows: sce_windows_fixture }.each do |mname, fix|
    context "with #{mname}" do
      # Don't use :let or :let! here because, for some reason, the objects are not properly
      # memoized and are re-created for each test. This is a huge performance hit.
      test_objs = []
      Dir.chdir(fix) do
        test_objs << AbideDevUtils::Ppt::PuppetModule.new
        test_objs << AbideDevUtils::Sce::Benchmark.benchmarks_from_puppet_module(test_objs.first)
      end

      context 'when supplied a PuppetModule' do
        it 'creates benchmark objects correctly' do
          expect(test_objs.last.empty?).not_to be_truthy
        end

        it 'creates the correct number of objects' do
          # We use greater than or equal to here because the number of benchmarks
          # should always be greater than or equal to the number of supported OSes
          # for the module. The reason it will be grater is because of supporting
          # multiple benchmarks for a single OS (e.g. STIG and CIS for RHEL)
          expect(test_objs.last.length).to be >= test_objs.first.supported_os.length
        end

        it 'creates objects with resource data' do
          expect(test_objs.last.all? { |b| !b.resource_data.nil? && !b.resource_data.empty? }).to be_truthy
        end

        it 'creates objects with mapping data' do
          expect(test_objs.last.all? { |b| !b.map_data.nil? && !b.map_data.empty? }).to be_truthy
        end

        it 'creates objects with title' do
          expect(test_objs.last.all? { |b| b.title.is_a?(String) && !b.title.empty? }).to be_truthy
        end

        it 'creates objects with version' do
          expect(test_objs.last.all? { |b| b.version.is_a?(String) && !b.version.empty? }).to be_truthy
        end

        it 'creates objects with title key' do
          expect(test_objs.last.all? { |b| b.title_key.is_a?(String) && !b.title_key.empty? }).to be_truthy
        end

        it 'creates objects with controls' do
          expect(test_objs.last.all? { |b| b.controls.is_a?(Array) && !b.controls.empty? }).to be_truthy
        end
      end
    end
  end
end
