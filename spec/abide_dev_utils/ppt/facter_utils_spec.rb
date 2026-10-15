# frozen_string_literal: true

require 'spec_helper'
require 'json'

RSpec.describe AbideDevUtils::Ppt::FacterUtils do
  describe AbideDevUtils::Ppt::FacterUtils::FactSets do
    subject(:fact_sets) { described_class.new }

    {
      %w[Amazon 2023] => 'RedHat',
      %w[RedHat 10] => 'RedHat',
      %w[OracleLinux 10] => 'RedHat',
      %w[Ubuntu 24.04] => 'Debian',
      %w[windows 2025] => 'windows'
    }.each do |(name, major), family|
      it "resolves facts for #{name} #{major} with os.family #{family}" do
        facts = fact_sets.find_by_fact_value_tuples(['os.name', name], ['os.release.major', major])
        expect(facts&.dig('os', 'family')).to eq(family)
      end
    end
  end

  # Local fact sets must be labeled with a Facter 4.x version so rspec-puppet-facts
  # selects them under Puppet 8 (see specifications/CEM-6998.md).
  describe 'files/fact_sets' do
    Dir.glob(File.expand_path('../../../files/fact_sets/*.facts', __dir__)).each do |path|
      it "#{File.basename(path)} is labeled with a Facter 4.x facterversion" do
        expect(JSON.parse(File.read(path))['facterversion']).to match(/\A4\.\d+\.\d+\z/)
      end
    end
  end
end
