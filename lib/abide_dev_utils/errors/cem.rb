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
  end
end
