# frozen_string_literal: true

require 'abide_dev_utils/errors/gcloud'

module AbideDevUtils
  module GCloud
    include AbideDevUtils::Errors::GCloud

    def self.storage_bucket(name: nil, project: nil, credentials: nil)
      raise MissingProjectError if project.nil? && ENV['ABIDE_GCLOUD_PROJECT'].nil?
      raise MissingCredentialsError if credentials.nil? && ENV['ABIDE_GCLOUD_CREDENTIALS'].nil?
      raise MissingBucketNameError if name.nil? && ENV['ABIDE_GCLOUD_BUCKET'].nil?

      require 'google/cloud/storage'
      @bucket = Google::Cloud::Storage.new(
        project_id: project || ENV['ABIDE_GCLOUD_PROJECT'],
        credentials: credentials || ENV['ABIDE_GCLOUD_CREDENTIALS']
      ).bucket(name || ENV['ABIDE_GCLOUD_BUCKET'])
    end
  end
end
