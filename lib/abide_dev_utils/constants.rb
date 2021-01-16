# frozen_string_literal: true

module AbideDevUtils
  module CliConstants
    require 'abide_dev_utils/config'
    require 'abide_dev_utils/errors'
    require 'abide_dev_utils/output'
    require 'abide_dev_utils/prompt'
    require 'abide_dev_utils/validate'

    CONFIG = AbideDevUtils::Config
    ERRORS = AbideDevUtils::Errors
    OUTPUT = AbideDevUtils::Output
    PROMPT = AbideDevUtils::Prompt
    VALIDATE = AbideDevUtils::Validate
  end
end
