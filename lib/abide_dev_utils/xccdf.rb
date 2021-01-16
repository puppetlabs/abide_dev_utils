# frozen_string_literal: true

require 'yaml'
require 'nokogiri'

module AbideDevUtils
  # Provides utilities around XCCDF file parsing
  module XCCDF
    CONTROL_PREFIX = /^[\d.]+_/.freeze

    def self.normalize_str(str)
      str.delete('-').gsub(/\s/, '_').downcase
    end

    def self.normalize_ctrl_name(ctrl)
      new_ctrl = ctrl.split('_rule_')[-1].gsub(CONTROL_PREFIX, '')
      normalize_str(new_ctrl)
    end

    def self.make_parent_key(doc, prefix)
      doc_title = normalize_str(doc.xpath('xccdf:Benchmark/xccdf:title').children.to_s)
      prefix.nil? ? doc_title : "#{prefix}#{doc_title}"
    end

    def self.to_hiera(xccdf_file, **kwargs)
      hiera_doc = {}
      doc = Nokogiri.XML(File.open(xccdf_file))
      parent_key = make_parent_key(doc, kwargs.dig('parent_key_prefix', nil))
      hiera_doc[parent_key] = {}
      profiles = doc.xpath('xccdf:Benchmark/xccdf:Profile')
      profiles.each do |p|
        title = normalize_str(p.xpath('./xccdf:title').children.to_s)
        hiera_doc[parent_key][title] = []
        selects = p.xpath('./xccdf:select')
        selects.each do |s|
          hiera_doc[parent_key][title] << normalize_ctrl_name(s['idref'].to_s)
        end
      end
      puts hiera_doc.to_yaml if kwargs.dig('out_file', nil).nil?
    end
  end
end
