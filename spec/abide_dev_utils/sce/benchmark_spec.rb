# frozen_string_literal: true

require 'spec_helper'

RSpec.describe('AbideDevUtils::Sce::Benchmark') do
  { sce_linux: sce_linux_fixture, sce_windows: sce_windows_fixture }.each do |mname, fix|
    context "with #{mname}" do
      # Don't use :let or :let! here because, for some reason, the objects are not properly
      # memoized and are re-created for each test. This is a huge performance hit.
      test_objs = []
      Dir.chdir(fix) do
        test_objs << AbideDevUtils::Ppt::PuppetModule.new
        test_objs << AbideDevUtils::Sce::BenchmarkLoader.benchmarks_from_puppet_module(
          ignore_framework_mismatch: true
        )
      end

      context 'when filtering controls by profile and level' do
        it 'excludes profiles not in the filter when both prof and lvl are given' do
          ctrl = test_objs.last.flat_map(&:controls)
                          .find { |c| c.profiles_levels.any? { |pl| pl.start_with?('workstation;;;') } }
          skip 'no control with workstation profile found in fixtures' unless ctrl
          result = ctrl.filtered_profiles_levels(prof: %w[server], lvl: %w[level_1 level_2])
          expect(result.none? { |pl| pl.start_with?('workstation;;;') }).to be(true)
        end
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
