# frozen_string_literal: true

require 'abide_dev_utils/errors/base'

module AbideDevUtils
  module Errors
    module GCloud
      class MissingCredentialsError < GenericError
        @default = <<~EOERR
          Storage credentials not given. Please set environment variable ABIDE_GCLOUD_CREDENTIALS.
        EOERR
      end

      class MissingProjectError < GenericError
        @default = <<~EOERR
          Storage project not given. Please set the environment variable ABIDE_GCLOUD_PROJECT.
        EOERR
      end

      class MissingBucketNameError < GenericError
        @default = <<~EOERR
          Storage bucket name not given. Please set the environment variable ABIDE_GCLOUD_BUCKET.
        EOERR
      end
    end
  end
end
