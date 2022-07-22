# frozen_string_literal: true

require 'spec_helper'
require 'abide_dev_utils/cem/coverage_report'

RSpec.describe('AbideDevUtils::CEM::CoverageReport') do
  { cem_linux: cem_linux_fixture, cem_windows: cem_windows_fixture }.each do |mname, fix|
    context "with #{mname}" do
      around do |example|
        Dir.chdir(fix) do
          example.run
        end
      end

      it 'processes basic coverage report' do
        cov_reps = AbideDevUtils::CEM::CoverageReport.basic_coverage
        binding.pry
        expect(cov_reps.empty?).not_to be_truthy
      end
    end
  end
end
