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

        attr_reader :title, :version

        # Creates a new Hiera object
        # @param xccdf_file [String] path to an XCCDF file
        # @param parent_key_prefix [String] a string to be prepended to the
        #   top-level key in the Hiera structure. Useful for namespacing
        #   the top-level key.
        def initialize(xccdf_file, parent_key_prefix: nil)
          @doc = parse(xccdf_file)
          @title = xpath(XPATHS[:benchmark][:title]).children.to_s
          @version = xpath(XPATHS[:benchmark][:version]).children.to_s
          @profiles = xpath(XPATHS[:profiles][:all])
          @parent_key = make_parent_key(@doc, parent_key_prefix)
          @hash = make_hash(@doc, @parent_key)
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
          yh = @hash[@parent_key.to_sym].transform_keys do |k|
            "#{@parent_key}::#{k}"
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

        attr_accessor :doc, :parent_key, :hash, :profiles

        def parse(xccdf_file)
          raise AbideDevUtils::Errors::FileNotFoundError, xccdf_file unless File.file?(xccdf_file)

          Nokogiri.XML(File.open(xccdf_file))
        end

        def make_hash(doc, parent_key)
          hash = { parent_key.to_sym => { title: @title, version: @version } }
          profiles = doc.xpath('xccdf:Benchmark/xccdf:Profile')
          profiles.each do |p|
            title = normalize_profile_name(p.xpath('./xccdf:title').children.to_s)
            hash[parent_key.to_sym][title.to_sym] = []
            selects = p.xpath('./xccdf:select')
            selects.each do |s|
              hash[parent_key.to_sym][title.to_sym] << normalize_ctrl_name(s['idref'].to_s)
            end
          end
          hash
        end

        def normalize_str(str)
          str.delete('-').gsub(/\s/, '_').downcase
        end

        def normalize_profile_name(prof)
          normalize_str("profile_#{prof}")
        end

        def normalize_ctrl_name(ctrl)
          new_ctrl = ctrl.split('_rule_')[-1].gsub(CONTROL_PREFIX, '')
          normalize_str(new_ctrl.gsub(/\./, '_'))
        end

        def make_parent_key(doc, prefix)
          doc_title = normalize_str(doc.xpath(XPATHS[:benchmark][:title]).children.to_s)
          if prefix.nil?
            doc_title
          else
            sepped_prefix = prefix.end_with?('::') ? prefix : "#{prefix}::"
            "#{sepped_prefix.chomp}#{doc_title}"
          end
        end
      end
    end
  end
end
