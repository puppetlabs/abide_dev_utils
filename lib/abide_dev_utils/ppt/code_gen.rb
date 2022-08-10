# frozen_string_literal: true

require 'abide_dev_utils/ppt/code_gen/data_types'
require 'abide_dev_utils/ppt/code_gen/resource'
require 'abide_dev_utils/ppt/code_gen/resource_types'

module AbideDevUtils
  module Ppt
    module CodeGen
      def self.generate_a_manifest
        Manifest.new
      end
    end
  end
end
