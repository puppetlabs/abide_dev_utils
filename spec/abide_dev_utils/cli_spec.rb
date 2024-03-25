# frozen_string_literal: true

require 'spec_helper'

commands = Dir.glob(File.join(__dir__, '../../lib/abide_dev_utils/cli/*.rb')).map { |f| File.basename(f, '.rb') }
commands.reject! { |f| f == 'abstract' }

# rubocop:disable RSpec/FilePath
# rubocop:disable RSpec/MultipleExpectations
# rubocop:disable RSpec/ExampleLength
RSpec.describe Abide::CLI do
  context 'with each command' do
    commands.each do |c|
      it "executes '#{c}' command with the help flag" do
        expect do
          output = capture_stdout { described_class.execute([c, '-h']) }
          expect(output).to match(/Developer tools for Abide/)
        end.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
      end
    end
  end

  context 'with Sce commands' do
    before do
      allow(AbideDevUtils::Output).to receive(:simple).and_return(nil)
      allow(AbideDevUtils::Output).to receive(:yaml).and_return(nil)
      allow(AbideDevUtils::Output).to receive(:json).and_return(nil)
    end

    it 'executes the "sce generate" command with the help flag' do
      expect do
        output = capture_stdout { described_class.execute(['sce', 'generate', '-h']) }
        expect(output).to match(/Developer tools for Abide/)
      end.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
    end

    it 'executes the "sce generate coverage-report" command with options' do
      expect(AbideDevUtils::Sce::Generate::CoverageReport).to(
        receive(:generate).with(
          {
            format_func: :to_h,
            opts: {
              benchmark: 'benchmark',
              profile: 'profile',
              level: 'level',
              ignore_benchmark_errors: true,
              xccdf_dir: 'xccdf_dir'
            }
          }
        ).and_return('Coverage report')
      )
      expect(AbideDevUtils::Output).to receive(:simple).with('Saving coverage report to test_file...')
      expect(AbideDevUtils::Output).to receive(:json).with('Coverage report', console: false, file: 'test_file')
      capture_stdout_stderr do
        described_class.execute(
          [
            'sce',
            'generate',
            'coverage-report',
            '-b', 'benchmark',
            '-p', 'profile',
            '-l', 'level',
            '-X', 'xccdf_dir',
            '-o', 'test_file',
            '-f', 'json',
            '-I'
          ]
        )
      end
    end

    it 'executes the "sce generate reference" command with options' do
      allow(AbideDevUtils::Validate).to receive(:puppet_module_directory).and_return(nil)
      expect(AbideDevUtils::Sce::Generate::Reference).to(
        receive(:generate).with(
          {
            out_file: 'test_file',
            format: 'markdown',
            debug: true,
            quiet: true,
            strict: true,
            select_profile: %w[profile1 profile2],
            select_level: %w[1 2]
          }
        )
      )
      capture_stdout_stderr do
        described_class.execute(
          [
            'sce',
            'generate',
            'reference',
            '-o', 'test_file',
            '-f', 'markdown',
            '-v',
            '-q',
            '-s',
            '-p', 'profile1,profile2',
            '-l', '1,2'
          ]
        )
      end
    end

    it 'executes the "sce update-config" command with the help flag' do
      expect do
        output = capture_stdout { described_class.execute(['sce', 'update-config', '-h']) }
        expect(output).to match(/Developer tools for Abide/)
      end.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
    end

    it 'executes the "sce update-config from-diff" command and gets warning' do
      expect do
        described_class.execute(%w[sce update-config from-diff config_file curr_xccdf new_xccdf])
      end.to output(/^This command is currently non-functional/).to_stderr
    end

    it 'executes the "sce validate" command with the help flag' do
      expect do
        output = capture_stdout { described_class.execute(['sce', 'validate', '-h']) }
        expect(output).to match(/Developer tools for Abide/)
      end.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
    end

    it 'executes the "sce validate puppet-strings" command with options' do
      ret_val = {
        one: [{ errors: [], warnings: [] }],
        two: [{ errors: [], warnings: [] }],
        three: [{ errors: [], warnings: [1] }],
        four: [{ errors: [], warnings: [2] }],
        five: [{ errors: [], warnings: [] }]
      }
      allow(AbideDevUtils::Validate).to receive(:puppet_module_directory).and_return(nil)
      expect(AbideDevUtils::Sce::Validate::Strings).to receive(:validate)
        .with(
          {
            format: 'json',
            verbose: true,
            quiet: true,
            out_file: 'test_file',
            strict: true
          }
        ).and_return(ret_val)
      expect(AbideDevUtils::Output).to receive(:json).with(
        ret_val,
        console: false,
        file: 'test_file',
        stringify: true
      )
      expect do
        capture_stdout_stderr do
          described_class.execute(
            [
              'sce',
              'validate',
              'puppet-strings',
              '-f', 'json',
              '-o', 'test_file',
              '-v',
              '-q',
              '-s'
            ]
          )
        end
      end.to raise_error(SystemExit) { |e| expect(e.success?).to be_falsey }
    end
  end
end
# rubocop:enable RSpec/FilePath
# rubocop:enable RSpec/MultipleExpectations
# rubocop:enable RSpec/ExampleLength
