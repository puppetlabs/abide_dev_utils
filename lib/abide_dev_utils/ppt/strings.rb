# frozen_string_literal: true

require 'puppet-strings'
require 'puppet-strings/yard'

module AbideDevUtils
  module Ppt
    # Puppet Strings reference object
    class Strings
      REGISTRY_TYPES = %i[
        root
        module
        class
        puppet_class
        puppet_data_type
        puppet_data_type_alias
        puppet_defined_type
        puppet_type
        puppet_provider
        puppet_function
        puppet_task
        puppet_plan
      ].freeze

      attr_reader :search_patterns

      def initialize(search_patterns: nil, **opts)
        check_yardoc_dir
        @search_patterns = search_patterns || PuppetStrings::DEFAULT_SEARCH_PATTERNS
        @debug = opts[:debug]
        @quiet = opts[:quiet]
        PuppetStrings::Yard.setup!
        YARD::CLI::Yardoc.run(*yard_args(@search_patterns, debug: @debug, quiet: @quiet))
      end

      def debug?
        !!@debug
      end

      def quiet?
        !!@quiet
      end

      def registry
        @registry ||= YARD::Registry.all(*REGISTRY_TYPES).map { |i| YardObjectWrapper.new(i) }
      end

      def find_resource(resource_name)
        to_h.each do |_, resources|
          res = resources.find { |r| r[:name] == resource_name.to_sym }
          return res if res
        end
      end

      def puppet_classes(hashed: false)
        reg_type(:puppet_class, hashed: hashed)
      end

      def data_types(hashed: false)
        reg_type(:puppet_data_types, hashed: hashed)
      end
      alias puppet_data_type data_types

      def data_type_aliases(hashed: false)
        reg_type(:puppet_data_type_alias, hashed: hashed)
      end
      alias puppet_data_type_alias data_type_aliases

      def defined_types(hashed: false)
        reg_type(:puppet_defined_type, hashed: hashed)
      end
      alias puppet_defined_type defined_types

      def resource_types(hashed: false)
        reg_type(:puppet_type, hashed: hashed)
      end
      alias puppet_type resource_types

      def providers(hashed: false)
        reg_type(:puppet_provider, hashed: hashed)
      end
      alias puppet_provider providers

      def puppet_functions(hashed: false)
        reg_type(:puppet_function, hashed: hashed)
      end
      alias puppet_function puppet_functions

      def puppet_tasks(hashed: false)
        reg_type(:puppet_task, hashed: hashed)
      end
      alias puppet_task puppet_tasks

      def puppet_plans(hashed: false)
        reg_type(:puppet_plan, hashed: hashed)
      end
      alias puppet_plan puppet_plans

      def to_h
        {
          puppet_classes: puppet_classes,
          data_types: data_types,
          data_type_aliases: data_type_aliases,
          defined_types: defined_types,
          resource_types: resource_types,
          providers: providers,
          puppet_functions: puppet_functions,
          puppet_tasks: puppet_tasks,
          puppet_plans: puppet_plans,
        }
      end

      private

      def check_yardoc_dir
        yardoc_dir = File.expand_path('./.yardoc')
        return unless Dir.exist?(yardoc_dir) && !File.writable?(yardoc_dir)

        raise "yardoc directory permissions error. Ensure #{yardoc_dir} is writable by current user."
      end

      def reg_type(reg_type, hashed: false)
        hashed ? hashes_for_reg_type(reg_type) : select_by_reg_type(reg_type)
      end

      def select_by_reg_type(reg_type)
        registry.select { |i| i.type == reg_type }
      end

      def hashes_for_reg_type(reg_type)
        all_to_h(select_by_reg_type(reg_type))
      end

      def all_to_h(objects)
        objects.sort_by(&:name).map(&:to_hash)
      end

      def yard_args(patterns, debug: false, quiet: false)
        args = ['doc', '--no-progress', '-n']
        args << '--debug' if debug && !quiet
        args << '--backtrace' if debug && !quiet
        args << '-q' if quiet
        args << '--no-stats' if quiet
        args += patterns
        args
      end
    end

    # Wrapper class for Yard objects that allows associating things like validators with them
    class YardObjectWrapper
      attr_accessor :validator
      attr_reader :object

      def initialize(object, validator: nil)
        @object = object
        @validator = validator
      end

      def method_missing(method, *args, &block)
        if object.respond_to?(method)
          object.send(method, *args, &block)
        elsif validator.respond_to?(method)
          validator.send(method, *args, &block)
        else
          super
        end
      end

      def respond_to_missing?(method, include_private = false)
        object.respond_to?(method) || validator.respond_to?(method) || super
      end

      def to_hash
        object.to_hash
      end
      alias to_h to_hash

      def to_s
        object.to_s
      end
    end
  end
end
