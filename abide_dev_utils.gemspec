# frozen_string_literal: true

require_relative "lib/abide_dev_utils/version"

Gem::Specification.new do |spec|
  spec.name          = "abide_dev_utils"
  spec.version       = AbideDevUtils::VERSION
  spec.authors       = ["Heston Snodgrass"]
  spec.email         = ["hsnodgrass3@gmail.com"]

  spec.summary       = "Helper utilities for writing compliance Puppet code."
  spec.description   = "Provides a CLI with utilities used for writing compliance Puppet code."
  spec.homepage      = ""
  spec.license       = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.4.0")

  # spec.metadata["allowed_push_host"] = "TODO: Set to 'http://mygemserver.com'"

  # spec.metadata["homepage_uri"] = spec.homepage
  # spec.metadata["source_code_uri"] = "TODO: Put your gem's public repo URL here."
  # spec.metadata["changelog_uri"] = "TODO: Put your gem's CHANGELOG.md URL here."

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{\A(?:test|spec|features)/}) }
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # Prod dependencies
  spec.add_dependency 'nokogiri', '~> 1.11'
  spec.add_dependency 'nokogiri-happymapper', '~> 0.8'

  # Dev dependencies
  spec.add_development_dependency 'rspec'
  spec.add_development_dependency 'rubocop', '~> 1.8', require: false
  spec.add_development_dependency 'rubocop-rspec'
  spec.add_development_dependency 'rubocop-performance'
  spec.add_development_dependency 'rubocop-i18n'
  spec.add_development_dependency 'fast_gettext'

  # For more information and examples about making a new gem, checkout our
  # guide at: https://bundler.io/guides/creating_gem.html
end
