# frozen_string_literal: true

require_relative File.expand_path('../lib/abide_dev_utils.rb', __dir__)
Dir.glob(File.expand_path('../lib/abide_dev_utils/**/*.rb', __dir__)).sort.each do |f|
  require_relative f
rescue LoadError => e
  puts "Error loading #{f}: #{e}"
end

module TestResources
  def fixtures_dir
    File.expand_path(File.join(__dir__, 'fixtures'))
  end

  def sce_linux_fixture
    sce_dir = File.join(fixtures_dir, 'puppetlabs-sce_linux')
    return sce_dir if Dir.exist?(sce_dir) && !Dir.empty?(sce_dir)

    File.join(fixtures_dir, 'puppetlabs-cem_linux')
  end

  def sce_windows_fixture
    sce_dir = File.join(fixtures_dir, 'puppetlabs-sce_windows')
    return sce_dir if Dir.exist?(sce_dir) && !Dir.empty?(sce_dir)

    File.join(fixtures_dir, 'puppetlabs-cem_windows')
  end

  def resources_dir
    File.expand_path(File.join(__dir__, "resources"))
  end

  def all_test_files
    Dir.glob(File.join(resources_dir, "test_files", "*"))
  end

  def test_xccdf_files
    all_test_files.select { |f| f.end_with?("-xccdf.xml") }
  end

  def lib_dir
    File.expand_path(File.join(__dir__, '..', 'lib'))
  end
end

module OutputHelpers
  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end

  def capture_stderr
    original_stderr = $stderr
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = original_stderr
  end

  def capture_stdout_stderr
    original_stdout = $stdout
    original_stderr = $stderr
    $stdout = StringIO.new
    $stderr = StringIO.new
    yield
    [$stdout.string, $stderr.string]
  ensure
    $stdout = original_stdout
    $stderr = original_stderr
  end
end

# If tests are slow, check this code out https://gist.github.com/palkan/73395cc201a565ecd3ff61aac44ad5ae
# Just don't keep it in the repo because it's unlicensed

RSpec.configure do |config|
  config.include TestResources
  config.extend TestResources
  config.include OutputHelpers
  config.extend OutputHelpers

  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.fail_fast = false

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
end
