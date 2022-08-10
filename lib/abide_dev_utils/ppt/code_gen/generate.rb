# frozen_string_literal: true

require 'abide_dev_utils/ppt/code_gen/resource_types'

module AbideDevUtils
  module Ppt
    module CodeGen
      module Generate
        def self.a_manifest
          AbideDevUtils::Ppt::CodeGen::Manifest.new
        end
      end
    end
  end
end
