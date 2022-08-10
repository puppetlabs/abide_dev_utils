# frozen_string_literal: true

require 'abide_dev_utils/ppt/code_gen/resource_types/base'

module AbideDevUtils
  module Ppt
    module CodeGen
      class Strings < Base
        VALID_CHILDREN = %w[See Summary Param Example].freeze
      end
    end
  end
end
