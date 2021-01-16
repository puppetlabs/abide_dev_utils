# frozen_string_literal: true

require 'yaml'

module AbideDevUtils
  module Config
    DEFAULT_PATH = "#{File.expand_path('~')}/.abide_dev.yaml"

    def self.to_h(path = DEFAULT_PATH)
      h = YAML.safe_load(File.open(path), [Symbol])
      h.transform_keys(&:to_sym)
    end

    def self.config_section(section, path = DEFAULT_PATH)
      h = to_h(path)
      s = h[section.to_sym]
      s.transform_keys(&:to_sym)
    end

    def self.fetch(key, default = nil, path = DEFAULT_PATH)
      to_h(path).fetch(key, default)
    end
  end
end
