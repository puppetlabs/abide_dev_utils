# frozen_string_literal: true

require 'yaml'
require 'nokogiri'
require 'abide_dev_utils/errors'

module AbideDevUtils
  module XCCDF
    module CIS
      # Creates a Hiera structure by parsing a CIS XCCDF benchmark
      # @!attribute [r] title
      # @!attribute [r] version
      # @!attribute [r] yaml_title
      class Hiera
        CONTROL_PREFIX = /^[\d.]+_/.freeze
        UNDERSCORED = /(\s|\(|\)|-|\.)/.freeze
        XPATHS = {
          benchmark: {
            all: 'xccdf:Benchmark',
            title: 'xccdf:Benchmark/xccdf:title',
            version: 'xccdf:Benchmark/xccdf:version'
          },
          profiles: {
            all: 'xccdf:Benchmark/xccdf:Profile',
            relative_title: './xccdf:title',
            relative_select: './xccdf:select'
          }
        }.freeze
        NEXT_GEN_WINDOWS = /(next_generation_windows_security)/.freeze

        attr_reader :title, :version

        # Creates a new Hiera object
        # @param xccdf_file [String] path to an XCCDF file
        # @param parent_key_prefix [String] a string to be prepended to the
        #   top-level key in the Hiera structure. Useful for namespacing
        #   the top-level key.
        def initialize(xccdf_file, parent_key_prefix: nil, num: false)
          @doc = parse(xccdf_file)
          @title = xpath(XPATHS[:benchmark][:title]).children.to_s
          @version = xpath(XPATHS[:benchmark][:version]).children.to_s
          @profiles = xpath(XPATHS[:profiles][:all])
          @parent_key = make_parent_key(@doc, parent_key_prefix)
          @hash = make_hash(@doc, num)
        end

        def yaml_title
          normalize_str(@title)
        end

        # Convert the Hiera object to a hash
        # @return [Hash]
        def to_h
          @hash
        end

        # Convert the Hiera object to a string
        # @return [String]
        def to_s
          @hash.inspect
        end

        # Convert the Hiera object to YAML string
        # @return [String] YAML-formatted string
        def to_yaml
          yh = @hash.transform_keys do |k|
            [@parent_key, k].join('::').strip
          end
          yh.to_yaml
        end

        # If a method gets called on the Hiera object which is not defined,
        # this sends that method call to hash, then doc, then super.
        def method_missing(method, *args, &block)
          return true if ['exist?', 'exists?'].include?(method.to_s)

          return @hash.send(method, *args, &block) if @hash.respond_to?(method)

          return @doc.send(method, *args, &block) if @doc.respond_to?(method)

          super(method, *args, &block)
        end

        # Checks the respond_to? of hash, doc, or super
        def respond_to_missing?(method_name, include_private = false)
          return true if ['exist?', 'exists?'].include?(method_name.to_s)

          @hash || @doc || super
        end

        private

        attr_accessor :doc, :hash, :parent_key, :profiles

        # Accepts a path to an xccdf xml file and returns a parsed Nokogiri object of the file
        # @param xccdf_file [String] path to an xccdf xml file
        # @return [Nokogiri::Node] A Nokogiri node object of the XML document
        def parse(xccdf_file)
          raise AbideDevUtils::Errors::FileNotFoundError, xccdf_file unless File.file?(xccdf_file)

          Nokogiri.XML(File.open(xccdf_file))
        end

        def make_hash(doc, num)
          hash = { 'title' => @title, 'version' => @version }
          profiles = doc.xpath('xccdf:Benchmark/xccdf:Profile')
          profiles.each do |p|
            title = normalize_profile_name(p.xpath('./xccdf:title').children.to_s)
            hash[title.to_s] = []
            selects = p.xpath('./xccdf:select')
            selects.each do |s|
              hash[title.to_s] << normalize_ctrl_name(s['idref'].to_s, num)
            end
          end
          hash
        end

        def normalize_str(str)
          nstr = str.downcase
          nstr.gsub!(/[^a-z0-9]$/, '')
          nstr.gsub!(/^[^a-z]/, '')
          nstr.gsub!(/^(l1_|l2_|ng_)/, '')
          nstr.delete!('(/|\\|\+)')
          nstr.gsub!(UNDERSCORED, '_')
          nstr.strip!
          nstr
        end

        def normalize_profile_name(prof)
          prof_name = normalize_str("profile_#{prof}")
          prof_name.gsub!(NEXT_GEN_WINDOWS, 'ngws')
          prof_name.strip!
          prof_name
        end

        def normalize_ctrl_name(ctrl, num)
          return num_normalize_ctrl(ctrl) if num

          name_normalize_ctrl(ctrl)
        end

        def name_normalize_ctrl(ctrl)
          new_ctrl = ctrl.split('benchmarks_rule_')[-1].gsub(CONTROL_PREFIX, '')
          normalize_str(new_ctrl)
        end

        def num_normalize_ctrl(ctrl)
          part = ctrl.split('benchmarks_rule_')[-1]
          numpart = CONTROL_PREFIX.match(part).to_s.chop.gsub(UNDERSCORED, '_')
          "c#{numpart}"
        end

        def make_parent_key(doc, prefix)
          doc_title = normalize_str(doc.xpath(XPATHS[:benchmark][:title]).children.to_s)
          return doc_title if prefix.nil?

          sepped_prefix = prefix.end_with?('::') ? prefix : "#{prefix}::"
          "#{sepped_prefix.chomp}#{doc_title}"
        end
      end
    end
  end
end
