# frozen_string_literal: true

require 'abide_dev_utils/ppt/code_gen/resource_types/base'

module AbideDevUtils
  module Ppt
    module CodeGen
      class Manifest < Base
        def initialize
          super
          @supports_children = true
        end
      end
    end
  end
end
