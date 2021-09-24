# frozen_string_literal: true

require 'abide_dev_utils/errors/base'

module AbideDevUtils
  module Errors
    module Comply
      class ComplyLoginFailedError < GenericError
        @default = 'Failed to login to Comply:'
      end
    end
  end
end
