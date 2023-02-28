# frozen_string_literal: true

require 'puppet-strings'
require 'puppet-strings/yard'

module AbideDevUtils
  # Puppet Strings reference object
  class PuppetStrings
    attr_reader :search_patterns

    def initialize(search_patterns: nil, opts: {})
      check_yardoc_dir
      @search_patterns = search_patterns || ::PuppetStrings::DEFAULT_SEARCH_PATTERNS
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

    def find_resource(resource_name)
      to_h.each do |_, resources|
        res = resources.find { |r| r[:name] == resource_name.to_sym }
        return res if res
      end
    end

    def puppet_classes
      @puppet_classes ||= all_to_h YARD::Registry.all(:puppet_class)
    end

    def data_types
      @data_types ||= all_to_h YARD::Registry.all(:puppet_data_types)
    end

    def data_type_aliases
      @data_type_aliases ||= all_to_h YARD::Registry.all(:puppet_data_type_alias)
    end

    def defined_types
      @defined_types ||= all_to_h YARD::Registry.all(:puppet_defined_type)
    end

    def resource_types
      @resource_types ||= all_to_h YARD::Registry.all(:puppet_type)
    end

    def providers
      @providers ||= all_to_h YARD::Registry.all(:puppet_provider)
    end

    def puppet_functions
      @puppet_functions ||= all_to_h YARD::Registry.all(:puppet_function)
    end

    def puppet_tasks
      @puppet_tasks ||= all_to_h YARD::Registry.all(:puppet_task)
    end

    def puppet_plans
      @puppet_plans ||= all_to_h YARD::Registry.all(:puppet_plan)
    end

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
end
