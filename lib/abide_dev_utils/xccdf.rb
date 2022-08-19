# frozen_string_literal: true

require 'yaml'
require 'hashdiff'
require 'nokogiri'
require 'abide_dev_utils/validate'
require 'abide_dev_utils/errors/xccdf'
require 'abide_dev_utils/output'

module AbideDevUtils
  # Contains modules and classes for working with XCCDF files
  module XCCDF
    # Generate map for CEM
    def self.gen_map(xccdf_file, **opts)
      type = opts.fetch(:type, 'cis')
      case type.downcase
      when 'cis'
        Benchmark.new(xccdf_file).gen_map(**opts)
      when 'stig'
        Benchmark.new(xccdf_file).gen_map(**opts)
      else
        raise AbideDevUtils::Errors::UnsupportedXCCDFError, "XCCDF type #{type} is unsupported!"
      end
    end

    # Converts and xccdf file to a Hiera representation
    def self.to_hiera(xccdf_file, opts)
      type = opts.fetch(:type, 'cis')
      case type.downcase
      when 'cis'
        Benchmark.new(xccdf_file).to_hiera(**opts)
      else
        raise AbideDevUtils::Errors::UnsupportedXCCDFError, "XCCDF type #{type} is unsupported!"
      end
    end

    # Diffs two xccdf files
    def self.diff(file1, file2, opts)
      require 'abide_dev_utils/xccdf/diff'
      bm1 = Benchmark.new(file1)
      bm2 = Benchmark.new(file2)
      AbideDevUtils::XCCDF::Diff.diff_benchmarks(bm1, bm2, opts)
    end

    # Use new-style diff
    def self.new_style_diff(file1, file2, opts)
      require 'abide_dev_utils/xccdf/diff/benchmark'
      bm_diff = AbideDevUtils::XCCDF::Diff::BenchmarkDiff.new(file1, file2, opts)
      bm_diff.diff
    end

    # Common constants and methods included by nearly everything else
    module Common
      XPATHS = {
        benchmark: {
          all: 'Benchmark',
          title: 'Benchmark/title',
          version: 'Benchmark/version'
        },
        cis: {
          profiles: {
            all: 'Benchmark/Profile',
            relative_title: './title',
            relative_select: './select'
          }
        }
      }.freeze
      CONTROL_PREFIX = /^[\d.]+_/.freeze
      UNDERSCORED = /(\s|\(|\)|-|\.)/.freeze
      CIS_TITLE_MARKER = 'CIS'
      CIS_NEXT_GEN_WINDOWS = /[Nn]ext_[Gg]eneration_[Ww]indows_[Ss]ecurity/.freeze
      CIS_CONTROL_NUMBER = /([0-9.]+[0-9]+)/.freeze
      CIS_LEVEL_CODE = /(?:_|^)([Ll]evel_[0-9]|[Ll]1|[Ll]2|[NnBb][GgLl]|#{CIS_NEXT_GEN_WINDOWS})/.freeze
      CIS_CONTROL_PARTS = /#{CIS_CONTROL_NUMBER}#{CIS_LEVEL_CODE}?_+([A-Za-z].*)/.freeze
      CIS_PROFILE_PARTS = /#{CIS_LEVEL_CODE}[_-]+([A-Za-z].*)/.freeze
      STIG_TITLE_MARKER = 'Security Technical Implementation Guide'
      STIG_CONTROL_PARTS = /(V-[0-9]+)/.freeze
      STIG_PROFILE_PARTS = /(MAC-\d+)_([A-Za-z].+)/.freeze
      PROFILE_PARTS = /#{CIS_PROFILE_PARTS}|#{STIG_PROFILE_PARTS}/.freeze
      CONTROL_PARTS = /#{CIS_CONTROL_PARTS}|#{STIG_CONTROL_PARTS}/.freeze

      def xpath(path)
        @xml.xpath(path)
      end

      def validate_xccdf(path)
        AbideDevUtils::Validate.file(path, extension: '.xml')
      end

      def normalize_string(str)
        nstr = str.dup.downcase
        nstr.gsub!(/[^a-z0-9]$/, '')
        nstr.gsub!(/^[^a-z]/, '')
        nstr.gsub!(/(?:_|^)([Ll]1_|[Ll]2_|ng_)/, '')
        nstr.delete!('(/|\\|\+)')
        nstr.gsub!(UNDERSCORED, '_')
        nstr.strip!
        nstr
      end

      def normalize_profile_name(prof, **_opts)
        prof_name = normalize_string("profile_#{control_profile_text(prof)}").dup
        prof_name.gsub!(CIS_NEXT_GEN_WINDOWS, 'ngws')
        prof_name.delete_suffix!('_environment_general_use')
        prof_name.delete_suffix!('sensitive_data_environment_limited_functionality')
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
        parts = control_profile_text(profile).match(PROFILE_PARTS)
        raise AbideDevUtils::Errors::ProfilePartsError, profile if parts.nil?

        if parts[1]
          # CIS profile
          parts[1].gsub!(/[Ll]evel_/, 'L')
          parts[1..2]
        elsif parts[3]
          # STIG profile
          parts[3..4]
        else
          raise AbideDevUtils::Errors::ProfilePartsError, profile
        end
      end

      def control_parts(control)
        mdata = control_profile_text(control).match(CONTROL_PARTS)
        raise AbideDevUtils::Errors::ControlPartsError, control if mdata.nil?

        if mdata[1]
          # CIS control
          mdata[1..3]
        elsif mdata[4]
          # STIG control
          vuln_id = mdata[4]
          group = @benchmark.xpath("Group[@id='#{vuln_id}']")
          if group.xpath('Rule').length != 1
            raise AbideDevUtils::Errors::ControlPartsError, control
          end
          rule_id = group.xpath('Rule/@id').first.value
          return [vuln_id, rule_id]
        else
          raise AbideDevUtils::Errors::ControlPartsError, control
        end
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

      def ==(other)
        diff_properties.map { |x| send(x) } == other.diff_properties.map { |x| other.send(x) }
      end

      def abide_object?
        true
      end
    end

    # Class representation of an XCCDF benchmark
    class Benchmark
      include AbideDevUtils::XCCDF::Common

      CIS_MAP_INDICES = %w[title hiera_title hiera_title_num number].freeze
      STIG_MAP_INDICES = %w[vulnid ruleid].freeze

      attr_reader :xml, :title, :version, :diff_properties, :benchmark

      def initialize(path)
        @xml = parse(path)
        @xml.remove_namespaces!
        @benchmark = xpath('Benchmark')
        @title = xpath('Benchmark/title').text
        @version = xpath('Benchmark/version').text
        @diff_properties = %i[title version profiles]
      end

      def normalized_title
        normalize_string(title)
      end

      def profiles
        @profiles ||= Profiles.new(xpath('Benchmark/Profile'), @benchmark)
      end

      def profile_levels
        @profiles.levels
      end

      def profile_titles
        @profiles.titles
      end

      def controls
        @controls ||= Controls.new(xpath('//select'))
      end

      def controls_by_profile_level(level_code)
        profiles.select { |x| x.level == level_code }.map(&:controls).flatten.uniq
      end

      def controls_by_profile_title(profile_title)
        profiles.select { |x| x.title == profile_title }.controls
      end

      def gen_map(dir: nil, type: 'cis', parent_key_prefix: '', version_output_dir: false, **_)
        case type
        when 'cis'
          os, ver = facter_platform
          indicies = CIS_MAP_INDICES
        when 'stig'
          os, ver = facter_benchmark
          indicies = STIG_MAP_INDICES
        end
        output_path = [type, os, ver]
        output_path.unshift(File.expand_path(dir)) if dir
        output_path << version if version_output_dir
        mapping_dir = File.expand_path(File.join(output_path))
        parent_key_prefix = '' if parent_key_prefix.nil?
        indicies.each_with_object({}) do |idx, h|
          map_file_path = "#{mapping_dir}/#{idx}.yaml"
          h[map_file_path] = map_indexed(indicies: indicies, index: idx, framework: type, key_prefix: parent_key_prefix)
        end
      end

      def find_cis_recommendation(name, number_format: false)
        profiles.each do |profile|
          profile.controls.each do |ctrl|
            return [profile, ctrl] if normalize_control_name(ctrl, number_format: number_format) == name
          end
        end
      end

      def to_h
        {
          title: title,
          version: version,
          profiles: profiles.to_h
        }
      end

      def map_indexed(indicies: [], index: 'title', framework: 'cis', key_prefix: '')
        c_map = profiles.each_with_object({}) do |profile, obj|
          obj[profile.level.downcase] = {} unless obj[profile.level.downcase].is_a?(Hash)
          obj[profile.level.downcase][profile.title.downcase] = map_controls_hash(profile, indicies, index).sort_by { |k, _| k }.to_h
        end

        c_map['benchmark'] = { 'title' => title, 'version' => version }
        mappings = [framework, index]
        mappings.unshift(key_prefix) unless key_prefix.empty?
        { mappings.join('::') => c_map }.to_yaml
      end

      def facter_benchmark
        id = xpath('Benchmark/@id').text
        id.split('_')[0..-2]
      end

      def facter_platform
        cpe = xpath('Benchmark/platform')[0]['idref'].split(':')
        if cpe.length > 4
          product_name = cpe[4].split('_')
          product_version = cpe[5].split('.') unless cpe[5].nil?
          return [product_name[0], product_version[0]] unless product_version[0] == '-'

          return [product_name[0], product_name[-1]] if product_version[0] == '-'
        end

        product = cpe[3].split('_')
        [product[0], product[-1]] # This should wrap the name i.e 'Windows' and the version '10'
      end

      # Converts object to Hiera-formatted YAML
      # @return [String] YAML-formatted string
      def to_hiera(parent_key_prefix: nil, num: false, levels: [], titles: [], **_kwargs)
        hash = { 'title' => title, 'version' => version }
        key_prefix = hiera_parent_key(parent_key_prefix)
        profiles.each do |profile|
          next unless levels.empty? || levels.include?(profile.level)
          next unless titles.empty? || titles.include?(profile.title)

          hash[profile.hiera_title] = hiera_controls_for_profile(profile, num)
        end
        hash.transform_keys! do |k|
          [key_prefix, k].join('::').strip
        end
        hash.to_yaml
      end

      def resolve_cis_control_reference(control)
        xpath("//Rule[@id='#{control.reference}']")
      end

      private

      def format_map_control_index(index, control)
        case index
        when 'hiera_title_num'
          control.hiera_title(number_format: true)
        when 'title'
          resolve_cis_control_reference(control).xpath('./title').text
        else
          control.send(index.to_sym)
        end
      end

      def map_controls_hash(profile, indicies, index)
        profile.controls.each_with_object({}) do |ctrl, hsh|
          control_array = indicies.each_with_object([]) do |idx_sym, ary|
            next if idx_sym == index

            item = format_map_control_index(idx_sym, ctrl)
            ary << item.to_s
          end
          hsh[format_map_control_index(index, ctrl)] = control_array.sort
        end
      end

      def parse(path)
        validate_xccdf(path)
        Nokogiri::XML.parse(File.open(File.expand_path(path))) do |config|
          config.strict.noblanks.norecover
        end
      end

      def find_profiles
        profs = {}
        xpath('Benchmark/Profile').each do |profile|
          level_code, name = profile_parts(profile['id'])
          profs[name] = {} unless profs.key?(name)
          profs[name][level_code] = profile
        end
        profs
      end

      def find_profile_names
        profiles.each_with_object([]) do |profile, ary|
          ary << "#{profile.level} #{profile.plain_text_title}"
        end
      end

      def hiera_controls_for_profile(profile, number_format)
        profile.controls.each_with_object([]) do |ctrl, ary|
          ary << ctrl.hiera_title(number_format: number_format)
        end
      end

      def hiera_parent_key(prefix)
        return normalized_title if prefix.nil?

        prefix.end_with?('::') ? "#{prefix}#{normalized_title}" : "#{prefix}::#{normalized_title}"
      end
    end

    class XccdfObject
      include AbideDevUtils::XCCDF::Common

      def initialize(benchmark)
        @benchmark = benchmark
        @benchmark_type = benchmark_type
      end

      def controls_class
        case @benchmark_type
        when :cis
          CisControls
        when :stig
          StigControls
        else
          raise AbideDevUtils::Errors::UnsupportedXCCDFError
        end
      end

      def control_sort_key
        case @benchmark_type
        when :cis
          :number
        when :stig
          :vulnid
        else
          raise AbideDevUtils::Errors::UnsupportedXCCDFError
        end
      end

      def control_class
        case @benchmark_type
        when :cis
          CisControl
        when :stig
          StigControl
        else
          raise AbideDevUtils::Errors::UnsupportedXCCDFError
        end
      end

      private

      def benchmark_type
        title = @benchmark.at_xpath('title').text
        if title.include?(STIG_TITLE_MARKER)
          return :stig
        elsif title.include?(CIS_TITLE_MARKER)
          return :cis
        end
        raise AbideDevUtils::Errors::UnsupportedXCCDFError, "XCCDF type is unsupported!"
      end
    end

    class ObjectContainer < XccdfObject
      include AbideDevUtils::XCCDF::Common

      def initialize(list, object_creation_method, benchmark, *args, **kwargs)
        super(benchmark)
        @object_list = send(object_creation_method.to_sym, list, benchmark, *args, **kwargs)
        @searchable = []
      end

      def method_missing(m, *args, &block)
        property = m.to_s.start_with?('search_') ? m.to_s.split('_')[-1].to_sym : nil
        return search(property, *args, &block) if property && @searchable.include?(property)
        return @object_list.send(m, *args, &block) if @object_list.respond_to?(m)

        super
      end

      def respond_to_missing?(m, include_private = false)
        return true if m.to_s.start_with?('search_') && @searchable.include?(m.to_s.split('_')[-1].to_sym)

        super
      end

      def to_h
        @object_list.each_with_object({}) do |obj, self_hash|
          key = resolve_hash_key(obj)
          self_hash[key] = obj.to_h
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

      def sorted_control_classes(raw_select_list, benchmark)
        raw_select_list.map { |x| control_class.new(x, benchmark) }.sort_by(&control_sort_key)
      end

      def sorted_profile_classes(raw_profile_list, benchmark)
        raw_profile_list.map { |x| Profile.new(x, benchmark) }.sort_by(&:title)
      end

      def resolve_hash_key(obj)
        return obj.send(:raw_title) unless defined?(@hash_key)

        @hash_key.each_with_object([]) { |x, a| a << obj.send(x) }.join('_')
      end

      def searchable!(*properties)
        @searchable = properties
      end

      def index!(property)
        @index = property
      end

      def hash_key!(*properties)
        @hash_key = properties
      end
    end

    class Profiles < ObjectContainer
      def initialize(list, benchmark)
        super(list, :sorted_profile_classes, benchmark)
        searchable! :level, :title
        index! :title
        hash_key! :level, :title
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

    class StigControls < ObjectContainer
      def initialize(list, benchmark)
        super(list, :sorted_control_classes, benchmark)
        searchable! :vulnid, :ruleid
        index! :vulnid
        hash_key! :vulnid
      end

      def vulnids
        @vulnids ||= @object_list.map(&:vulnid).sort
      end

      def ruleids
        @ruleids ||= @object_list.map(&:ruleid).sort
      end

      def include_vulnid?(item)
        @object_list.map(&:vulnid).include?(item)
      end

      def include_ruleid?(item)
        @object_list.map(&:ruleid).include?(item)
      end
    end

    class CisControls < ObjectContainer
      def initialize(list, benchmark)
        super(list, :sorted_control_classes, benchmark)
        searchable! :level, :title, :number
        index! :number
        hash_key! :number
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

    class XccdfElement < XccdfObject
      include AbideDevUtils::XCCDF::Common

      def initialize(element, benchmark)
        super(benchmark)
        @xml = element
        @element_type = self.class.name.split('::').last.downcase
        @raw_title = control_profile_text(element)
      end

      def to_h
        @properties.each_with_object({}) do |pair, hash|
          hash[pair[0]] = if pair[1].nil?
                            send(pair[0])
                          else
                            obj = send(pair[0])
                            obj.send(pair[1])
                          end
        end
      end

      def to_s
        @hash.inspect
      end

      def reference
        @reference ||= @element_type.include?('control') ? @xml['idref'] : @xml['id']
      end

      def hiera_title(**opts)
        e_type = @element_type.include?('control') ? 'control' : 'profile'
        send("normalize_#{e_type}_name".to_sym, @xml, **opts)
      end

      private

      attr_reader :xml

      def properties(*plain_props, **props)
        plain_props.each { |x| props[x] = nil }
        props.transform_keys!(&:to_sym)
        self.class.class_eval do
          attr_reader :raw_title, :diff_properties

          plain_props.each { |x| attr_reader x.to_sym unless respond_to?(x) }
          props.each_key { |k| attr_reader k.to_sym unless respond_to?(k) }
        end
        @diff_properties = props.keys
        @properties = props
      end
    end

    class Profile < XccdfElement
      def initialize(profile, benchmark)
        super(profile, benchmark)
        @level, @title = profile_parts(control_profile_text(profile))
        @plain_text_title = @xml.xpath('./title').text
        @controls = controls_class.new(xpath('./select'), benchmark)
        properties :title, :level, :plain_text_title, controls: :to_h
      end
    end

    class StigControl < XccdfElement
      def initialize(control, benchmark)
        super(control, benchmark)
        @vulnid, @ruleid = control_parts(control_profile_text(control))
        properties :vulnid, :ruleid
      end
    end

    class CisControl < XccdfElement
      def initialize(control, benchmark)
        super(control, benchmark)
        @number, @level, @title = control_parts(control_profile_text(control))
        properties :number, :level, :title
      end
    end
  end
end
