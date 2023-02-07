# frozen_string_literal: true

require 'abide_dev_utils/errors/base'

module AbideDevUtils
  module Errors
    module Jira
      class CreateIssueError < GenericError
        @default = 'Failed to create Jira issue:'
      end

      class CreateEpicError < GenericError
        @default = 'Failed to create Jira epic:'
      end

      class CreateSubtaskError < GenericError
        @default = 'Failed to create Jira subtask for issue:'
      end

      class FindIssueError < GenericError
        @default = 'Failed to find Jira issue:'
      end
    end
  end
end
