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
    def self.simple_section_separator(section_text, sepchar: '#', width: 60, **_)
      section_text = section_text.to_s
      section_text = section_text[0..width - 4] if section_text.length > width
      section_text = " #{section_text} "
      section_sep_line = sepchar * width
      [section_sep_line, section_text.center(width, sepchar), section_sep_line].join("\n")
    end

    def self.simple(msg, stream: $stdout, **_)
      case msg
      when Hash
        stream.puts JSON.pretty_generate(msg)
      else
        stream.puts msg
      end
    end

    def self.text(msg, console: false, file: nil, **_)
      simple(msg) if console
      FWRITER.write_text(msg, file: file) unless file.nil?
    end

    def self.json(in_obj, console: false, file: nil, pretty: true, **_)
      AbideDevUtils::Validate.hashable(in_obj)
      json_out = pretty ? JSON.pretty_generate(in_obj) : JSON.generate(in_obj)
      simple(json_out) if console
      FWRITER.write_json(json_out, file: file) unless file.nil?
    end

    def self.yaml(in_obj, console: false, file: nil, stringify: false, **_)
      yaml_out = if in_obj.is_a? String
                   in_obj
                 else
                   AbideDevUtils::Validate.hashable(in_obj)
                   if stringify
                     JSON.parse(JSON.generate(in_obj)).to_yaml
                   else
                     # Use object's #to_yaml method if it exists, convert to hash if not
                     in_obj.respond_to?(:to_yaml) ? in_obj.to_yaml : in_obj.to_h.to_yaml
                   end
                 end
      simple(yaml_out) if console
      FWRITER.write_yaml(yaml_out, file: file) unless file.nil?
    end

    def self.yml(in_obj, console: false, file: nil, **_)
      AbideDevUtils::Validate.hashable(in_obj)
      # Use object's #to_yaml method if it exists, convert to hash if not
      yml_out = in_obj.respond_to?(:to_yaml) ? in_obj.to_yaml : in_obj.to_h.to_yaml
      simple(yml_out) if console
      FWRITER.write_yml(yml_out, file: file) unless file.nil?
    end

    def self.progress(title: 'Progress', start: 0, total: 100, format: nil, **_)
      ProgressBar.create(title: title, starting_at: start, total: total, format: format)
    end
  end
end
