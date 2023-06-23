# frozen_string_literal: true

require_relative 'files'

module AbideDevUtils
  module Config
    DEFAULT_PATH = "#{File.expand_path('~')}/.abide_dev.yaml"

    def self.to_h(path = DEFAULT_PATH)
      return {} unless File.file?(path)

      h = AbideDevUtils::Files::Reader.read(path)
      h.transform_keys(&:to_sym)
    end

    def to_h(path = DEFAULT_PATH)
      self.class.to_h(path)
    end

    def self.config_section(section, path = DEFAULT_PATH)
      h = to_h(path)
      s = h.fetch(section.to_sym, nil)
      return {} if s.nil?

      s.transform_keys(&:to_sym)
    end

    def config_section(section, path = DEFAULT_PATH)
      h = to_h(path)
      s = h.fetch(section.to_sym, nil)
      return {} if s.nil?

      s.transform_keys(&:to_sym)
    end

    def self.fetch(key, default = nil, path = DEFAULT_PATH)
      to_h(path).fetch(key, default)
    end

    def fetch(key, default = nil, path = DEFAULT_PATH)
      to_h(path).fetch(key, default)
    end
  end
end
