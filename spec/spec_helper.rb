# frozen_string_literal: true

require "abide_dev_utils"

module TestResources
  def resources_dir
    File.expand_path(File.join(__dir__, "resources"))
  end

  def all_test_files
    Dir.glob(File.join(resources_dir, "test_files", "*"))
  end

  def test_xccdf_files
    all_test_files.select { |f| f.end_with?("-xccdf.xml") }
  end
end

RSpec.configure do |config|
  config.include TestResources
  config.extend TestResources

  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
