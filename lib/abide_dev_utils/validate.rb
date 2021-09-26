# frozen_string_literal: true

require 'abide_dev_utils/errors'

module AbideDevUtils
  module Validate
    def self.filesystem_path(path)
      raise AbideDevUtils::Errors::FileNotFoundError, path unless File.exist?(path)
    end

    def self.file(path, extension: nil)
      filesystem_path(path)
      raise AbideDevUtils::Errors::PathNotFileError, path unless File.file?(path)
      return if extension.nil?

      file_ext = extension.match?(/^\.[A-Za-z0-9]+$/) ? extension : ".#{extension}"
      raise AbideDevUtils::Errors::FileExtensionIncorrectError, extension unless File.extname(path) == file_ext
    end

    def self.directory(path)
      filesystem_path(path)
      raise AbideDevUtils::Errors::PathNotDirectoryError, path unless File.directory?(path)
    end

    def self.not_empty(thing, msg)
      raise AbideDevUtils::Errors::ObjectEmptyError, msg if thing.empty?
    end

    def self.hashable(obj)
      return if obj.respond_to?(:to_hash) || obj.respond_to?(:to_h)

      raise AbideDevUtils::Errors::NotHashableError, obj
    end
  end
end
