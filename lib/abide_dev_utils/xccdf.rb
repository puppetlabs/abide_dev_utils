# frozen_string_literal: true

require 'yaml'
require 'hashdiff'
require 'nokogiri'
require 'abide_dev_utils/validate'
require 'abide_dev_utils/errors'
require 'abide_dev_utils/output'

module AbideDevUtils
  module XCCDF
    def self.to_hiera(xccdf_file, opts = {})
      type = opts.fetch(:type, 'cis')
      case type.downcase
      when 'cis'
        Hiera.new(xccdf_file, parent_key_prefix: opts[:parent_key_prefix], num: opts[:num])
      else
        AbideDevUtils::Output.simple("XCCDF type #{type} is unsupported!")
      end
    end

    def self.diff(file1, file2, **opts)
      bm1 = Benchmark.new(file1)
      bm2 = Benchmark.new(file2)
      profile = opts.fetch(:profile, nil).nil?
      diffreport = if profile.nil?
                     bm1.diff(bm2)
                   else
                     bm1.profiles.search_title(profile).diff(bm2.profiles.search_title(profile))
                   end
      AbideDevUtils::Output.yaml(diffreport, console: true, file: opts.fetch(:outfile, nil))
    end

    module Common
      CIS_XPATHS = {
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
      CONTROL_PREFIX = /^[\d.]+_/.freeze
      UNDERSCORED = /(\s|\(|\)|-|\.)/.freeze
      CIS_NEXT_GEN_WINDOWS = /(next_generation_windows_security)/.freeze
      CIS_CONTROL_NUMBER = /([0-9.]+[0-9]+)/.freeze
      CIS_LEVEL_CODE = /([Ll]1|[Ll]2|NG|ng|BL|bl)/.freeze
      CIS_CONTROL_PARTS = /#{CIS_CONTROL_NUMBER}_+#{CIS_LEVEL_CODE}_+([A-Za-z].*)/.freeze
      CIS_PROFILE_PARTS = /[A-Za-z_]+#{CIS_LEVEL_CODE}[_-]+([A-Za-z].*)/.freeze

      def xpath(path)
        @xml.xpath(path)
      end

      def validate_xccdf(path)
        AbideDevUtils::Validate.file(path, extension: '.xml')
      end

      def normalize_string(str)
        nstr = str.downcase
        nstr.gsub!(/[^a-z0-9]$/, '')
        nstr.gsub!(/^[^a-z]/, '')
        nstr.gsub!(/^([Ll]1_|[Ll]2_|ng_)/, '')
        nstr.delete!('(/|\\|\+)')
        nstr.gsub!(UNDERSCORED, '_')
        nstr.strip!
        nstr
      end

      def normalize_profile_name(prof)
        prof_name = normalize_string("profile_#{prof}")
        prof_name.gsub!(CIS_NEXT_GEN_WINDOWS, 'ngws')
        prof_name.strip!
        prof_name
      end

      def normalize_control_name(control, number_format: false)
        return number_normalize_control(control) if number_format

        name_normalize_control(control)
      end

      def name_normalize_control(control)
        normalize_string(control_profile_text(control).gsub(CONTROL_PREFIX, ''))
      end

      def number_normalize_control(control)
        numpart = CONTROL_PREFIX.match(control_profile_text(control)).to_s.chop.gsub(UNDERSCORED, '_')
        "c#{numpart}"
      end

      def text_normalize(control)
        control_profile_text(control).tr('_', ' ')
      end

      def profile_parts(profile)
        control_profile_text(profile).match(CIS_PROFILE_PARTS)[1..2]
      end

      def control_parts(control)
        control_profile_text(control).match(CIS_CONTROL_PARTS)[1..3]
      end

      def control_profile_text(item)
        return item.raw_title if item.respond_to?(:abide_object?)

        if item.respond_to?(:split)
          return item.split('benchmarks_rule_')[-1] if item.include?('benchmarks_rule_')

          item.split('benchmarks_profile_')[-1]
        else
          return item['idref'].to_s.split('benchmarks_rule_')[-1] if item.name == 'select'

          item['id'].to_s.split('benchmarks_profile_')[-1]
        end
      end

      def sorted_control_classes(raw_select_list, sort_key: :number)
        raw_select_list.map { |x| Control.new(x) }.sort_by(&sort_key)
      end

      def sorted_profile_classes(raw_profile_list, sort_key: :title)
        raw_profile_list.map { |x| Profile.new(x) }.sort_by(&sort_key)
      end

      def ==(other)
        diff_properties.map { |x| send(x) } == other.diff_properties.map { |x| other.send(x) }
      end

      def diff(other, similarity: 1, strict: false, strip: true, **opts)
        Hashdiff.diff(to_h, other.to_h, similarity: similarity, strict: strict, strip: strip, **opts)
      end

      def abide_object?
        true
      end
    end

    # Creates a Hiera structure by parsing a CIS XCCDF benchmark
    # @!attribute [r] title
    # @!attribute [r] version
    # @!attribute [r] yaml_title
    class Hiera
      include AbideDevUtils::XCCDF::Common

      attr_reader :title, :version

      # Creates a new Hiera object
      # @param xccdf_file [String] path to an XCCDF file
      # @param parent_key_prefix [String] a string to be prepended to the
      #   top-level key in the Hiera structure. Useful for namespacing
      #   the top-level key.
      def initialize(xccdf_file, parent_key_prefix: nil, num: false)
        @doc = parse(xccdf_file)
        @title = xpath(CIS_XPATHS[:benchmark][:title]).children.to_s
        @version = xpath(CIS_XPATHS[:benchmark][:version]).children.to_s
        @profiles = xpath(CIS_XPATHS[:profiles][:all])
        @parent_key = make_parent_key(@doc, parent_key_prefix)
        @hash = make_hash(@doc, number_format: num)
      end

      def yaml_title
        normalize_string(@title)
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

      def parse(path)
        validate_xccdf(path)
        Nokogiri::XML(File.open(File.expand_path(path))) do |config|
          config.strict.noblanks.norecover
        end
      end

      def make_hash(doc, number_format: false)
        hash = { 'title' => @title, 'version' => @version }
        profiles = doc.xpath('xccdf:Benchmark/xccdf:Profile')
        profiles.each do |p|
          title = normalize_profile_name(p.xpath('./xccdf:title').children.to_s)
          hash[title.to_s] = []
          selects = p.xpath('./xccdf:select')
          selects.each do |s|
            hash[title.to_s] << normalize_control_name(s['idref'].to_s, number_format: number_format)
          end
        end
        hash
      end

      def make_parent_key(doc, prefix)
        doc_title = normalize_string(doc.xpath(CIS_XPATHS[:benchmark][:title]).children.to_s)
        return doc_title if prefix.nil?

        sepped_prefix = prefix.end_with?('::') ? prefix : "#{prefix}::"
        "#{sepped_prefix.chomp}#{doc_title}"
      end
    end

    class Benchmark
      include AbideDevUtils::XCCDF::Common

      attr_reader :title, :version, :diff_properties

      def initialize(path)
        @xml = parse(path)
        @title = xpath('xccdf:Benchmark/xccdf:title').text
        @version = xpath('xccdf:Benchmark/xccdf:version').text
        @diff_properties = %i[title version profiles]
      end

      def profiles
        @profiles ||= Profiles.new(xpath('xccdf:Benchmark/xccdf:Profile'))
      end

      def profile_levels
        @profiles.levels
      end

      def profile_titles
        @profiles.titles
      end

      def controls
        @controls ||= Controls.new(xpath('//xccdf:select'))
      end

      def controls_by_profile_level(level_code)
        profiles.select { |x| x.level == level_code }.map(&:controls).flatten.uniq
      end

      def controls_by_profile_title(profile_title)
        profiles.select { |x| x.title == profile_title }.controls
      end

      def all_cis_recommendations
        controls
      end

      def find_cis_recommendation(name, number_format: false)
        controls.each do |ctrl|
          return ctrl if normalize_control_name(ctrl, number_format: number_format) == name
        end
      end

      def to_h
        {
          title: title,
          version: version,
          profiles: profiles.to_h
        }
      end

      def diff_profiles(other)
        profiles.diff(other.profiles)
      end

      def diff_controls(other)
        controls.diff(other.controls)
      end

      private

      def parse(path)
        validate_xccdf(path)
        Nokogiri::XML(File.open(File.expand_path(path))) do |config|
          config.strict.noblanks.norecover
        end
      end

      def sorted_profile_classes(raw_profile_list, sort_key: :level)
        raw_profile_list.map { |x| Profile.new(x) }.sort_by(&sort_key)
      end

      def find_profiles
        profs = {}
        xpath('xccdf:Benchmark/xccdf:Profile').each do |profile|
          level_code, name = profile_parts(profile['id'])
          profs[name] = {} unless profs.key?(name)
          profs[name][level_code] = profile
        end
        profs
      end

      def find_profile_names
        names = []
        profiles.each do |level, profs|
          profs.each do |name, _|
            names << "#{level} #{name}"
          end
        end
        names
      end
    end

    class ObjectContainer
      include AbideDevUtils::XCCDF::Common

      def initialize(list, object_creation_method)
        @object_list = send(object_creation_method.to_sym, list)
        @searchable = []
      end

      def method_missing(m, *args, &block)
        property = m.to_s.start_with?('search_') ? m.to_s.split('_')[-1].to_sym : nil
        super if property.nil? || !@searchable.include?(property)

        search(property, *args, &block)
      end

      def respond_to_missing?(m, include_private = false)
        return true if m.to_s.start_with?('search_') && @searchable.include?(m.to_s.split('_')[-1].to_sym)

        super
      end

      def to_h
        key_prop = @index.nil? ? :raw_title : @index
        @object_list.each_with_object({}) do |obj, self_hash|
          self_hash[obj.send(key_prop)] = obj.to_h.reject { |k, _| k == key_prop }
        end
      end

      def search(property, item)
        max = @object_list.length - 1
        min = 0
        while min <= max
          mid = (min + max) / 2
          return @object_list[mid] if @object_list[mid].send(property.to_sym) == item

          if @object_list[mid].send(property.to_sym) > item
            max = mid - 1
          else
            min = mid + 1
          end
        end
        nil
      end

      private

      def searchable!(*properties)
        @searchable = properties
      end

      def index!(property)
        @index = property
      end
    end

    class Profiles < ObjectContainer
      def initialize(list)
        super(list, :sorted_profile_classes)
        searchable! :level, :title
        index! :title
      end

      def levels
        @levels ||= @object_list.map(&:level).sort
      end

      def titles
        @titles ||= @object_list.map(&:title).sort
      end

      def include_level?(item)
        levels.include?(item)
      end

      def include_title?(item)
        titles.include?(item)
      end
    end

    class Controls < ObjectContainer
      def initialize(list)
        super(list, :sorted_control_classes)
        searchable! :level, :title, :number
        index! :number
      end

      def numbers
        @numbers ||= @object_list.map(&:number).sort
      end

      def levels
        @levels ||= @object_list.map(&:level).sort
      end

      def titles
        @titles ||= @object_list.map(&:title).sort
      end

      def include_number?(item)
        numbers.include?(item)
      end

      def include_level?(item)
        levels.include?(item)
      end

      def include_title?(item)
        titles.include?(item)
      end
    end

    class Profile
      include AbideDevUtils::XCCDF::Common

      attr_reader :raw_title, :title, :level, :diff_properties

      def initialize(profile)
        @xml = profile
        @raw_title = control_profile_text(profile)
        @level, @title = profile_parts(control_profile_text(profile))
      end

      def controls
        @controls ||= Controls.new(xpath('./xccdf:select'))
      end

      def to_h
        {
          title: title,
          level: level,
          controls: controls.to_h
        }
      end
    end

    class Control
      include AbideDevUtils::XCCDF::Common

      attr_reader :raw_title, :number, :level, :title, :diff_properties

      def initialize(control)
        @xml = control
        @raw_title = control_profile_text(control)
        @number, @level, @title = control_parts(control_profile_text(control))
        @diff_properties = %i[number level title]
      end

      def to_h
        {
          number: number,
          level: level,
          title: title
        }
      end
    end
  end
end
