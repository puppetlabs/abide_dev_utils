# frozen_string_literal: true

require 'abide_dev_utils/errors/base'

module AbideDevUtils
  module Errors
    # Raised by Benchmark when mapping data cannot be loaded
    class MappingFilesNotFoundError < GenericError
      @default = 'Mapping files not found using facts:'
    end

    # Raised by Benchmark when mapping files are not found for the specified framework
    class MappingDataFrameworkMismatchError < GenericError
      @default = 'Mapping data could not be found for the specified framework:'
    end

    # Raised by Benchmark when resource data cannot be loaded
    class ResourceDataNotFoundError < GenericError
      @default = 'Resource data not found using facts:'
    end

    # Raised by Control when it can't find mapping data for itself
    class NoMappingDataForControlError < GenericError
      @default = 'No mapping data found for control:'
    end

    # Raised by a control when it's given ID and framework are incompatible
    class ControlIdFrameworkMismatchError < GenericError
      @default = 'Control ID is invalid with the given framework:'
    end

    # Raised when a benchmark fails to load for a non-specific reason
    class BenchmarkLoadError < GenericError
      attr_accessor :framework, :osname, :major_version, :module_name, :original_error

      @default = 'Error loading benchmark:'

      def message
        [
          "#{super} (#{original_error.class})",
          "Framework: #{framework}",
          "OS Name: #{osname}",
          "OS Version: #{major_version}",
          "Module Name: #{module_name}"
        ].join(', ')
      end
    end
  end
end
