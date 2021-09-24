# frozen_string_literal: true

require 'abide_dev_utils/output'
require 'abide_dev_utils/validate'
require 'abide_dev_utils/xccdf/cis'

module AbideDevUtils
  module XCCDF
    def self.parse(xccdf_file)
      AbideDevUtils::Validate.file(xccdf_file)
      Nokogiri.XML(File.open(xccdf_file))
    end

    def self.to_hiera(xccdf_file, opts = {})
      type = opts.fetch(:type, 'cis')
      case type.downcase
      when 'cis'
        AbideDevUtils::XCCDF::CIS::Hiera.new(xccdf_file, parent_key_prefix: opts[:parent_key_prefix], num: opts[:num])
      else
        AbideDevUtils::Output.simple("XCCDF type #{type} is unsupported!")
      end
    end

    class UtilsObject
      require 'abide_dev_utils/xccdf/utils'
      extend AbideDevUtils::XCCDF::Utils
    end
  end
end
