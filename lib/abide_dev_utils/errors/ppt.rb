# frozen_string_literal: true

require 'abide_dev_utils/errors/base'

module AbideDevUtils
  module Errors
    module Ppt
      class NotModuleDirError < GenericError
        @default = 'Path is not a Puppet module directory:'
      end

      class ObjClassPathError < GenericError
        @default = 'Invalid path for class:'
      end

      class CustomObjPathKeyError < GenericError
        @default = 'Custom Object value hash does not have :path key: '
      end

      class CustomObjNotFoundError < GenericError
        @default = 'Could not find custom object in map:'
      end

      class TemplateNotFoundError < GenericError
        @default = 'Template does not exist at:'
      end

      class FailedToCreateFileError < GenericError
        @default = 'Failed to create file:'
      end

      class ClassFileNotFoundError < GenericError
        @default = 'Class file was not found:'
      end

      class ClassDeclarationNotFoundError < GenericError
        @default = 'Class declaration was not found:'
      end

      class InvalidClassNameError < GenericError
        @default = 'Not a valid Puppet class name:'
      end
    end
  end
end
