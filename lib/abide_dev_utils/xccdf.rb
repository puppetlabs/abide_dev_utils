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
      bm1 = Benchmark.new(file1)
      bm2 = Benchmark.new(file2)
      profile = opts.fetch(:profile, nil)
      profile_diff = if profile.nil?
                       bm1.diff_profiles(bm2).each do |_, v|
                         v.transform_values! { |x| x.map!(&:to_s) }
                       end
                     else
                       bm1.diff_profiles(bm2)[profile].transform_values! { |x| x.map!(&:to_s) }
                     end
      profile_key = profile.nil? ? 'all_profiles' : profile
      {
        'benchmark' => bm1.diff_title_version(bm2),
        profile_key => profile_diff
      }
    end

    # Common constants and methods included by nearly everything else
    module Common
      XPATHS = {
        benchmark: {
          all: 'xccdf:Benchmark',
          title: 'xccdf:Benchmark/xccdf:title',
          version: 'xccdf:Benchmark/xccdf:version'
        },
        cis: {
          profiles: {
            all: 'xccdf:Benchmark/xccdf:Profile',
            relative_title: './xccdf:title',
            relative_select: './xccdf:select'
          }
        }
      }.freeze
      CONTROL_PREFIX = /^[\d.]+_/.freeze
      UNDERSCORED = /(\s|\(|\)|-|\.)/.freeze
      CIS_NEXT_GEN_WINDOWS = /[Nn]ext_[Gg]eneration_[Ww]indows_[Ss]ecurity/.freeze
      CIS_CONTROL_NUMBER = /([0-9.]+[0-9]+)/.freeze
      CIS_LEVEL_CODE = /(?:_|^)([Ll]evel_[0-9]|[Ll]1|[Ll]2|[NnBb][GgLl]|#{CIS_NEXT_GEN_WINDOWS})/.freeze
      CIS_CONTROL_PARTS = /#{CIS_CONTROL_NUMBER}#{CIS_LEVEL_CODE}?_+([A-Za-z].*)/.freeze
      CIS_PROFILE_PARTS = /#{CIS_LEVEL_CODE}[_-]+([A-Za-z].*)/.freeze

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
        parts = control_profile_text(profile).match(CIS_PROFILE_PARTS)
        raise AbideDevUtils::Errors::ProfilePartsError, profile if parts.nil?

        parts[1].gsub!(/[Ll]evel_/, 'L')
        parts[1..2]
      end

      def control_parts(control, parent_level: nil)
        mdata = control_profile_text(control).match(CIS_CONTROL_PARTS)
        raise AbideDevUtils::Errors::ControlPartsError, control if mdata.nil?

        mdata[2] = parent_level unless parent_level.nil?
        mdata[1..3]
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

      def default_diff_opts
        {
          similarity: 1,
          strict: true,
          strip: true,
          array_path: true,
          delimiter: '//',
          use_lcs: false
        }
      end

      def diff(other, **opts)
        Hashdiff.diff(
          to_h,
          other.to_h,
          default_diff_opts.merge(opts)
        )
      end

      def abide_object?
        true
      end
    end

    # Class representation of an XCCDF benchmark
    class Benchmark
      include AbideDevUtils::XCCDF::Common

      MAP_INDICES = %w[title hiera_title hiera_title_num number].freeze

      attr_reader :xml, :title, :version, :diff_properties

      def initialize(path)
        @xml = parse(path)
        @title = xpath('xccdf:Benchmark/xccdf:title').text
        @version = xpath('xccdf:Benchmark/xccdf:version').text
        @diff_properties = %i[title version profiles]
      end

      def normalized_title
        normalize_string(title)
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

      def gen_map(dir: nil, type: 'CIS', parent_key_prefix: '', **_)
        os, ver = facter_platform
        mapping_dir = dir ? File.expand_path(File.join(dir, type, os, ver)) : ''
        parent_key_prefix = '' if parent_key_prefix.nil?
        MAP_INDICES.each_with_object({}) do |idx, h|
          map_file_path = "#{mapping_dir}/#{idx}.yaml"
          h[map_file_path] = map_indexed(index: idx, framework: type, key_prefix: parent_key_prefix)
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

      def diff_title_version(other)
        Hashdiff.diff(
          to_h.reject { |k, _| k.to_s == 'profiles' },
          other.to_h.reject { |k, _| k.to_s == 'profiles' },
          default_diff_opts
        )
      end

      def diff_profiles(other)
        this_diff = {}
        other_hash = other.to_h[:profiles]
        to_h[:profiles].each do |name, data|
          diff_h = Hashdiff.diff(data, other_hash[name], default_diff_opts).each_with_object({}) do |x, a|
            val_to = x.length == 4 ? x[3] : nil
            a_key = x[2].is_a?(Hash) ? x[2][:title] : x[2]
            a[a_key] = [] unless a.key?(a_key)
            a[a_key] << ChangeSet.new(change: x[0], key: x[1], value: x[2], value_to: val_to)
          end
          this_diff[name] = diff_h
        end
        this_diff
      end

      def diff_controls(other)
        controls.diff(other.controls)
      end

      def map_indexed(index: 'title', framework: 'cis', key_prefix: '')
        c_map = profiles.each_with_object({}) do |profile, obj|
          obj[profile.level.downcase] = {} unless obj[profile.level.downcase].is_a?(Hash)
          obj[profile.level.downcase][profile.title.downcase] = map_controls_hash(profile, index).sort_by { |k, _| k }.to_h
        end

        c_map['benchmark'] = { 'title' => title, 'version' => version }
        mappings = [framework, index]
        mappings.unshift(key_prefix) unless key_prefix.empty?
        { mappings.join('::') => c_map }.to_yaml
      end

      def facter_platform
        cpe = xpath('xccdf:Benchmark/xccdf:platform')[0]['idref'].split(':')
        [cpe[4].split('_')[0], cpe[5].split('.')[0]]
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

      def resolve_control_reference(control)
        xpath("//xccdf:Rule[@id='#{control.reference}']")
      end

      private

      def format_map_control_index(index, control)
        case index
        when 'hiera_title_num'
          control.hiera_title(number_format: true)
        when 'title'
          resolve_control_reference(control).xpath('./xccdf:title').text
        else
          control.send(index.to_sym)
        end
      end

      def map_controls_hash(profile, index)
        profile.controls.each_with_object({}) do |ctrl, hsh|
          control_array = MAP_INDICES.each_with_object([]) do |idx_sym, ary|
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

    class ChangeSet
      attr_reader :change, :key, :value, :value_to

      def initialize(change:, key:, value:, value_to: nil)
        validate_change(change)
        @change = change
        @key = key
        @value = value
        @value_to = value_to
      end

      def to_s
        val_to_str = value_to.nil? ? ' ' : " to #{value_to} "
        "#{change_string} value #{value}#{val_to_str}at #{key}"
      end

      def can_merge?(other)
        return false unless (change == '-' && other.change == '+') || (change == '+' && other.change == '-')
        return false unless key == other.key || value_hash_equality(other)

        true
      end

      def merge(other)
        unless can_merge?(other)
          raise ArgumentError, 'Cannot merge. Possible causes: change is identical; key or value do not match'
        end

        new_to_value = value == other.value ? nil : other.value
        ChangeSet.new(
          change: '~',
          key: key,
          value: value,
          value_to: new_to_value
        )
      end

      private

      def value_hash_equality(other)
        equality = false
        value.each do |k, v|
          equality = true if v == other.value[k]
        end
        equality
      end

      def validate_change(change)
        raise ArgumentError, "Change type #{change} in invalid" unless ['+', '-', '~'].include?(change)
      end

      def change_string
        case change
        when '-'
          'remove'
        when '+'
          'add'
        else
          'change'
        end
      end
    end

    class ObjectContainer
      include AbideDevUtils::XCCDF::Common

      def initialize(list, object_creation_method, *args, **kwargs)
        @object_list = send(object_creation_method.to_sym, list, *args, **kwargs)
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
      def initialize(list)
        super(list, :sorted_profile_classes)
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

    class Controls < ObjectContainer
      def initialize(list)
        super(list, :sorted_control_classes)
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

    class XccdfElement
      include AbideDevUtils::XCCDF::Common

      def initialize(element)
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
        @reference ||= @element_type == 'control' ? @xml['idref'] : @xml['id']
      end

      def hiera_title(**opts)
        send("normalize_#{@element_type}_name".to_sym, @xml, **opts)
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
      def initialize(profile)
        super(profile)
        @level, @title = profile_parts(control_profile_text(profile))
        @plain_text_title = @xml.xpath('./xccdf:title').text
        @controls = Controls.new(xpath('./xccdf:select'))
        properties :title, :level, :plain_text_title, controls: :to_h
      end
    end

    class Control < XccdfElement
      def initialize(control, parent_level: nil)
        super(control)
        @number, @level, @title = control_parts(control_profile_text(control), parent_level: parent_level)
        properties :number, :level, :title
      end
    end
  end
end
