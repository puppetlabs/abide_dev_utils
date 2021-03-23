# frozen_string_literal: true

require 'erb'
require 'pathname'
require 'abide_dev_utils/prompt'
require 'abide_dev_utils/errors/ppt'

module AbideDevUtils
  module Ppt
    class NewObjectBuilder
      DEFAULT_EXT = '.pp'

      def initialize(obj_type, obj_name, opts: {}, vars: {})
        @obj_type = obj_type
        @obj_name = namespace_format(obj_name)
        @opts = opts
        @vars = vars
        class_vars
        validate_class_vars
      end

      attr_reader :obj_type, :obj_name, :tmpl_name, :root_dir, :tmpl_dir, :tmpl_path, :type_path_map, :obj_path, :vars

      def render
        ERB.new(File.read(@tmpl_path.to_s), 0, '<>-').result(binding)
      end

      def build
        continue = File.exist?(obj_path) ? AbideDevUtils::Prompt.yes_no('File exists, would you like to overwrite?') : true
        return "Not overwriting file #{obj_path}" unless continue

        dir, = Pathname.new(obj_path).split
        Pathname.new(dir).mkpath unless Dir.exist?(dir)
        content = render
        File.open(obj_path, 'w') { |f| f.write(render) } unless content.empty?
        raise AbideDevUtils::Errors::Ppt::FailedToCreateFileError, obj_path unless File.file?(obj_path)

        "Created file #{obj_path}"
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

      def class_vars
        @tmpl_name = @opts.fetch(:tmpl_name, "#{@obj_type}.erb")
        @root_dir = Pathname.new(@opts.fetch(:root_dir, Dir.pwd))
        @tmpl_dir = if @opts.fetch(:absolute_template_dir, false)
                      @opts.fetch(:tmpl_dir)
                    else
                      "#{@opts.fetch(:root_dir, Dir.pwd)}/#{@opts.fetch(:tmpl_dir, 'object_templates')}"
                    end
        @tmpl_path = Pathname.new("#{@tmpl_dir}/#{@opts.fetch(:tmpl_name, "#{@obj_type}.erb")}")
        @type_path_map = @opts.fetch(:type_path_map, {})
        @obj_path = new_obj_path
      end

      def validate_class_vars
        raise AbideDevUtils::Errors::PathNotDirectoryError, @root_dir unless Dir.exist? @root_dir
        raise AbideDevUtils::Errors::PathNotDirectoryError, @tmpl_dir unless Dir.exist? @tmpl_dir
        raise AbideDevUtils::Errors::Ppt::TemplateNotFoundError, @tmpl_path.to_s unless @tmpl_path.file?
      end

      def basename(obj_name)
        obj_name.split('::')[-1]
      end

      def new_obj_path
        if obj_type == 'class'
          obj_path_from_name
        else
          custom_obj_path
        end
      end

      def namespace_format(name)
        name.split(':').reject(&:empty?).join('::')
      end

      def obj_path_from_name
        parts = @obj_name.split('::')[1..-2]
        parts.insert(0, 'manifests')
        parts.insert(-1, "#{basename(@obj_name)}#{DEFAULT_EXT}")
        path = @root_dir + Pathname.new(parts.join('/'))
        path.to_s
      end

      def custom_obj_path
        map_val = type_path_map.fetch(@obj_type.to_sym, nil)
        return obj_path_from_name if map_val.nil?

        if map_val.respond_to?(:key?)
          custom_obj_path_from_hash(map_val, @obj_name)
        else
          abs_path = Pathname.new(map_val).absolute? ? map_val : "#{Dir.pwd}/#{map_val}"
          "#{abs_path}/#{basename(@obj_name)}#{DEFAULT_EXT}"
        end
      end

      def custom_obj_path_from_hash(map_val, obj_name)
        raise AbideDevUtils::Errors::Ppt::CustomObjPathKeyError, map_val unless map_val.key?(:path)

        abs_path = Pathname.new(map_val[:path]).absolute? ? map_val[:path] : "#{Dir.pwd}/#{map_val[:path]}"
        if map_val.key?(:extension)
          "#{abs_path}/#{basename(obj_name)}#{map_val[:extension]}"
        else
          "#{abs_path}/#{basename(obj_name)}#{DEFAULT_EXT}"
        end
      end
    end
  end
end
