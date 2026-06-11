# frozen_string_literal: true

require 'spec_helper'
require 'abide_dev_utils/sce/generate/reference'

RSpec.describe(AbideDevUtils::Sce::Generate::Reference::MarkdownGenerator) do
  before do
    md_double = double('Markdown').as_null_object # rubocop:disable RSpec/VerifiedDoubles
    allow(AbideDevUtils::Markdown).to receive(:new).and_return(md_double)
  end

  context 'with puppetlabs-sce_linux and no select_profile' do
    it 'defaults select_profile to server' do
      gen = described_class.new([], 'puppetlabs-sce_linux', file: '/dev/null', opts: {})
      gen.generate
      expect(gen.instance_variable_get(:@opts)[:select_profile]).to eq(['server'])
    end
  end

  context 'with puppetlabs-sce_linux and explicit select_profile' do
    it 'does not override select_profile' do
      gen = described_class.new([], 'puppetlabs-sce_linux', file: '/dev/null',
                                                            opts: { select_profile: ['server'] })
      gen.generate
      expect(gen.instance_variable_get(:@opts)[:select_profile]).to eq(['server'])
    end
  end

  context 'with a non-sce_linux module and no select_profile' do
    it 'does not set a default select_profile' do
      gen = described_class.new([], 'puppetlabs-sce_windows', file: '/dev/null', opts: {})
      gen.generate
      expect(gen.instance_variable_get(:@opts)[:select_profile].nil?).to be(true)
    end
  end
end
