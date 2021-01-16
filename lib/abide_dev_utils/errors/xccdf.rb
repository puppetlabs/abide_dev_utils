# frozen_string_literal: true

require 'abide_dev_utils/errors/base'

module AbideDevUtils
  module Errors
    # Raised when an xpath search of an xccdf file fails
    class XPathSearchError < GenericError
      @default = 'XPath seach failed to find anything at:'
    end
  end
end
