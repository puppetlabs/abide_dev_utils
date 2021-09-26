# frozen_string_literal: true

require 'abide_dev_utils/errors/base'

module AbideDevUtils
  module Errors
    # Raised when something is empty and it shouldn't be
    class ObjectEmptyError < GenericError
      @default = 'Object is empty and should not be:'
    end

    # Raised when a an object is initialized with a nil param
    class NewObjectParamNilError < GenericError
      @default = 'Object init parameter is nil and should not be:'
    end

    # Raised when a file path does not exist
    class FileNotFoundError < GenericError
      @default = 'File not found:'
    end

    # Raised when a file path is not a regular file
    class PathNotFileError < GenericError
      @default = 'Path is not a regular file:'
    end

    # Raised when the path is not a directory
    class PathNotDirectoryError < GenericError
      @default = 'Path is not a directory:'
    end

    # Raised when a file extension is not correct
    class FileExtensionIncorrectError < GenericError
      @default = 'File extension does not match specified extension:'
    end

    # Raised when a searched for service is not found in the parser
    class ServiceNotFoundError < GenericError
      @default = 'Service not found:'
    end

    # Raised when getting an InetdConfConfig object that does not exist
    class ConfigObjectNotFoundError < GenericError
      @default = 'Config object not found:'
    end

    # Raised when adding an InetdConfConfig object that already exists
    class ConfigObjectExistsError < GenericError
      @default = 'Config object already exists:'
    end

    # Raised when an object should respond to :to_hash or :to_h and doesn't
    class NotHashableError < GenericError
      @default = 'Object does not respond to #to_hash or #to_h:'
    end
  end
end
