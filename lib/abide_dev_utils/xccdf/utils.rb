# frozen_string_literal: true

require 'abide_dev_utils/validate'

module AbideDevUtils
  module XCCDF
    module Utils
      # Class for working with directories that contain XCCDF files
      class FileDir
        CIS_FILE_NAME_PARTS_PATTERN = /^CIS_(?<subject>[A-Za-z0-9._()-]+)_Benchmark_v(?<version>[0-9.]+)-xccdf$/.freeze
        def initialize(path)
          @path = File.expand_path(path)
          AbideDevUtils::Validate.directory(@path)
        end

        def files
          @files ||= Dir.glob(File.join(@path, '*-xccdf.xml')).map { |f| FileNameData.new(f) }
        end

        def fuzzy_find(label, value)
          files.find { |f| f.fuzzy_match?(label, value) }
        end

        def fuzzy_select(label, value)
          files.select { |f| f.fuzzy_match?(label, value) }
        end

        def fuzzy_reject(label, value)
          files.reject { |f| f.fuzzy_match?(label, value) }
        end

        def label?(label)
          files.select { |f| f.has?(label) }
        end

        def no_label?(label)
          files.reject { |f| f.has?(label) }
        end
      end

      # Parses XCCDF file names into labeled parts
      class FileNameData
        CIS_PATTERN = /^CIS_(?<subject>[A-Za-z0-9._()-]+?)(?<stig>_STIG)?_Benchmark_v(?<version>[0-9.]+)-xccdf$/.freeze

        attr_reader :path, :name, :labeled_parts

        def initialize(path)
          @path = path
          @name = File.basename(path, '.xml')
          @labeled_parts = File.basename(name, '.xml').match(CIS_PATTERN)&.named_captures
        end

        def subject
          @subject ||= labeled_parts&.fetch('subject', nil)
        end

        def stig
          @stig ||= labeled_parts&.fetch('subject', nil)
        end

        def version
          @version ||= labeled_parts&.fetch('version', nil)
        end

        def has?(label)
          val = send(label.to_sym)
          !val.nil? && !val.empty?
        end

        def fuzzy_match?(label, value)
          return false unless has?(label)

          this_val = normalize_char_array(send(label.to_sym).chars)
          other_val = normalize_char_array(value.chars)
          other_val.each_with_index do |c, idx|
            return false unless this_val[idx] == c
          end
          true
        end

        private

        def normalize_char_array(char_array)
          char_array.grep_v(/[^A-Za-z0-9]/).map(&:downcase)[3..]
        end
      end
    end
  end
end
