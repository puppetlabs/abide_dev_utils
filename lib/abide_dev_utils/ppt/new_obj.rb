# frozen_string_literal: true

require 'erb'
require 'pathname'
require 'abide_dev_utils/output'
require 'abide_dev_utils/prompt'
require 'abide_dev_utils/errors/ppt'

module AbideDevUtils
  module Ppt
    class NewObjectBuilder
      DEFAULT_EXT = '.pp'
      VALID_EXT = /(\.pp|\.rb)\.erb$/.freeze
      TMPL_PATTERN = /^[a-zA-Z][^\s]*\.erb$/.freeze
      OBJ_PREFIX = /^(c-|d-)/.freeze
      PREFIX_TEST_PATH = { 'c-' => 'classes', 'd-' => 'defines' }.freeze

      def initialize(obj_type, obj_name, opts: {}, vars: {})
        @obj_type = obj_type
        @obj_name = namespace_format(obj_name)
        @opts = opts
        @vars = vars
        class_vars
        validate_class_vars
        @tmpl_data = template_data(@opts.fetch(:tmpl_name, @obj_type))
      end

      attr_reader :obj_type, :obj_name, :root_dir, :tmpl_dir, :obj_path, :vars, :tmpl_data

      def build
        force = @opts.fetch(:force, false)
        obj_cont = force ? true : continue?(obj_path)
        spec_cont = force ? true : continue?(@tmpl_data[:spec_path])
        write_file(obj_path, @tmpl_data[:path]) if obj_cont
        write_file(@tmpl_data[:spec_path], @spec_tmpl) if spec_cont
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

      def continue?(path)
        continue = if File.exist?(path)
                     AbideDevUtils::Prompt.yes_no('File exists, would you like to overwrite?')
                   else
                     true
                   end
        AbideDevUtils::Output.simple("Not overwriting file #{path}") unless continue

        continue
      end

      def write_file(path, tmpl_path)
        dir, = Pathname.new(path).split
        Pathname.new(dir).mkpath unless Dir.exist?(dir)
        content = render(tmpl_path)
        File.open(path, 'w') { |f| f.write(content) } unless content.empty?
        raise AbideDevUtils::Errors::Ppt::FailedToCreateFileError, path unless File.file?(path)

        AbideDevUtils::Output.simple("Created file #{path}")
      end

      def build_obj; end

      def class_vars
        @root_dir = Pathname.new(@opts.fetch(:root_dir, Dir.pwd))
        @tmpl_dir = if @opts.fetch(:absolute_template_dir, false)
                      @opts.fetch(:tmpl_dir)
                    else
                      "#{@root_dir}/#{@opts.fetch(:tmpl_dir, 'object_templates')}"
                    end
        @obj_path = new_obj_path
        @spec_tmpl = @opts.fetch(:spec_template, File.expand_path(File.join(__dir__, '../resources/generic_spec.erb')))
      end

      def validate_class_vars
        raise AbideDevUtils::Errors::PathNotDirectoryError, @root_dir unless Dir.exist? @root_dir
        raise AbideDevUtils::Errors::PathNotDirectoryError, @tmpl_dir unless Dir.exist? @tmpl_dir
      end

      def basename(obj_name)
        obj_name.split('::')[-1]
      end

      def prefix
        pfx = basename.match(OBJ_PREFIX)
        return pfx[1] unless pfx.empty?
      end

      def templates
        return [] if Dir.entries(tmpl_dir).empty?

        file_names = Dir.entries(tmpl_dir).select { |f| f.match?(TMPL_PATTERN) }
        file_names.map { |i| File.join(tmpl_dir, i) }
      end

      def template_data(query)
        raise AbideDevUtils::Errors::Ppt::TemplateNotFoundError, @tmpl_dir if Dir.entries(@tmpl_dir).empty?

        data = {}
        pattern = /#{Regexp.quote(query)}/
        templates.each do |i|
          pn = Pathname.new(i)
          next unless pn.basename.to_s.match?(pattern)

          data[:path] = pn.to_s
          data[:fname] = pn.basename.to_s
        end
        raise AbideDevUtils::Errors::Ppt::TemplateNotFoundError, @tmpl_dir unless data.key?(:fname)

        data[:ext] = data[:fname].match?(VALID_EXT) ? data[:fname].match(VALID_EXT)[1] : '.pp'
        data[:pfx] = data[:fname].match?(OBJ_PREFIX) ? data[:fname].match(OBJ_PREFIX)[1] : 'c-'
        data[:spec_base] = PREFIX_TEST_PATH[data[:pfx]]
        data[:obj_name] = normalize_obj_name(data.dup)
        data[:spec_name] = "#{@obj_name.split('::')[-1]}_spec.rb"
        data[:spec_path] = spec_path(data[:spec_base], data[:spec_name])
        data
      end

      def normalize_obj_name(data)
        new_name = data[:fname].slice(/^(?:#{Regexp.quote(data[:pfx])})?(?<name>[^\s.]+)(?:#{Regexp.quote(data[:ext])})?\.erb$/, 'name')
        "#{new_name}#{data[:ext]}"
      end

      def render(path)
        ERB.new(File.read(path), 0, '<>-').result(binding)
      end

      def namespace_format(name)
        name.split(':').reject(&:empty?).join('::')
      end

      def new_obj_path
        parts = @obj_name.split('::')[1..-2]
        parts.insert(0, 'manifests')
        parts.insert(-1, "#{basename(@obj_name)}#{DEFAULT_EXT}")
        path = @root_dir + Pathname.new(parts.join('/'))
        path.to_s
      end

      def spec_path(base_dir, spec_name)
        parts = @obj_name.split('::')[1..-2]
        parts.insert(0, 'spec')
        parts.insert(1, base_dir)
        parts.insert(-1, spec_name)
        path = @root_dir + Pathname.new(parts.join('/'))
        path.to_s
      end
    end
  end
end
