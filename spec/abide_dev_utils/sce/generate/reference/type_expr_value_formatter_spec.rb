# frozen_string_literal: true

require 'spec_helper'
require 'abide_dev_utils/sce/generate/reference'

RSpec.describe(AbideDevUtils::Sce::Generate::Reference::TypeExprValueFormatter) do
  describe '.yaml_flow' do
    it 'formats a flat hash as YAML flow style' do
      expect(described_class.yaml_flow({ 'target' => 'DROP' })).to eq('{target: DROP}')
    end

    it 'formats a nested hash as YAML flow style' do
      expect(described_class.yaml_flow({ 'public' => { 'target' => 'DROP' } })).to eq('{public: {target: DROP}}')
    end

    it 'formats an array as YAML flow style' do
      expect(described_class.yaml_flow(['lo'])).to eq('[lo]')
    end

    it 'formats a hash containing an array as YAML flow style' do
      expect(described_class.yaml_flow({ 'trusted' => { 'interfaces' => ['lo'] } })).to eq('{trusted: {interfaces: [lo]}}')
    end

    it 'returns a string value unchanged' do
      expect(described_class.yaml_flow('DROP')).to eq('DROP')
    end

    it 'converts non-string scalars to string' do
      expect(described_class.yaml_flow(42)).to eq('42')
    end
  end

  describe '.quote' do
    it 'wraps a string in double-quotes using inspect' do
      expect(described_class.quote('hello')).to eq('"hello"')
    end

    it 'formats a hash as YAML flow style instead of Ruby hash-rocket syntax' do
      result = described_class.quote({ 'public' => { 'target' => 'DROP' } })
      expect(result).to eq('{public: {target: DROP}}')
      expect(result).not_to include('=>')
    end

    it 'formats an array as YAML flow style' do
      expect(described_class.quote(['lo'])).to eq('[lo]')
    end

    it 'returns other values as-is' do
      expect(described_class.quote(true)).to eq(true)
    end
  end
end
