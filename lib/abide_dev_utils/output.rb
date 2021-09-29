# frozen_string_literal: true

require 'json'
require 'pp'
require 'yaml'
require 'ruby-progressbar'
require 'abide_dev_utils/validate'
require 'abide_dev_utils/files'

module AbideDevUtils
  module Output
    FWRITER = AbideDevUtils::Files::Writer.new
    def self.simple(msg, stream: $stdout)
      stream.puts msg
    end

    def self.json(in_obj, console: false, file: nil, pretty: true)
      AbideDevUtils::Validate.hashable(in_obj)
      json_out = pretty ? JSON.pretty_generate(in_obj) : JSON.generate(in_obj)
      simple(json_out) if console
      FWRITER.write_json(json_out, file: file) unless file.nil?
    end

    def self.yaml(in_obj, console: false, file: nil)
      yaml_out = if in_obj.is_a? String
                   in_obj
                 else
                   AbideDevUtils::Validate.hashable(in_obj)
                   # Use object's #to_yaml method if it exists, convert to hash if not
                   in_obj.respond_to?(:to_yaml) ? in_obj.to_yaml : in_obj.to_h.to_yaml
                 end
      simple(yaml_out) if console
      FWRITER.write_yaml(yaml_out, file: file) unless file.nil?
    end

    def self.yml(in_obj, console: false, file: nil)
      AbideDevUtils::Validate.hashable(in_obj)
      # Use object's #to_yaml method if it exists, convert to hash if not
      yml_out = in_obj.respond_to?(:to_yaml) ? in_obj.to_yaml : in_obj.to_h.to_yaml
      simple(yml_out) if console
      FWRITER.write_yml(yml_out, file: file) unless file.nil?
    end

    def self.progress(title: 'Progress', start: 0, total: 100)
      ProgressBar.create(title: title, starting_at: start, total: total)
    end
  end
end
