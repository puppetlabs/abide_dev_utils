# frozen_string_literal: true

require 'abide_dev_utils/ppt/code_gen/resource_types/base'

module AbideDevUtils
  module Ppt
    module CodeGen
      class Parameter < Base
        def initialize
          @supports_children = true
          @supports_value = true
        end
      end
    end
  end
end
