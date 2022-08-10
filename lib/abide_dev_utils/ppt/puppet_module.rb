# frozen_string_literal: true

require 'json'
require 'yaml'
require 'abide_dev_utils/validate'
require 'abide_dev_utils/ppt/hiera'

module AbideDevUtils
  module Ppt
    # Class for working with Puppet Modules
    class PuppetModule
      DEF_FILES = {
        metadata: 'metadata.json',
        readme: 'README.md',
        reference: 'REFERENCE.md',
        changelog: 'CHANGELOG.md',
        hiera_config: 'hiera.yaml',
        fixtures: '.fixtures.yml',
        rubocop: '.rubocop.yml',
        sync: '.sync.yml',
        pdkignore: '.pdkignore',
        gitignore: '.gitignore'
      }.freeze

      attr_reader :directory, :special_files

      def initialize(directory = Dir.pwd)
        AbideDevUtils::Validate.directory(directory)
        @directory = directory
        @special_files = DEF_FILES.dup.transform_values { |v| File.expand_path(File.join(@directory, v)) }
      end

      def name(strip_namespace: false)
        strip_namespace ? metadata['name'].split('-')[-1] : metadata['name']
      end

      def metadata
        @metadata ||= JSON.parse(File.read(special_files[:metadata]))
      end

      def supported_os
        @supported_os ||= find_supported_os
      end

      def hiera_conf
        @hiera_conf ||= AbideDevUtils::Ppt::Hiera::Config.new(special_files[:hiera_config])
      end

      private

      def find_supported_os
        return [] unless metadata['operatingsystem_support']

        metadata['operatingsystem_support'].each_with_object([]) do |os, arr|
          os['operatingsystemrelease'].each do |r|
            arr << "#{os['operatingsystem']}::#{r}"
          end
        end
      end

      def in_dir
        return unless block_given?

        current = Dir.pwd
        if current == File.expand_path(directory)
          yield
        else
          Dir.chdir(directory)
          yield
          Dir.chdir(current)
        end
      end
    end
  end
end
