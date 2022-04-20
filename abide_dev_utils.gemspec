# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "abide_dev_utils/version"

Gem::Specification.new do |spec|
  spec.name          = "abide_dev_utils"
  spec.version       = AbideDevUtils::VERSION
  spec.authors       = ["abide-team"]
  spec.email         = ["abide-team@puppet.com"]

  spec.summary       = "Helper utilities for developing compliance Puppet code"
  spec.description   = "Provides a CLI with helpful utilities for developing compliance Puppet code"
  spec.homepage      = "https://github.com/puppetlabs/abide_dev_utils"
  spec.license       = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.7.0")

  # spec.metadata["allowed_push_host"] = "TODO: Set to 'http://mygemserver.com'"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = spec.homepage

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{\A(?:test|spec|features)/}) }
  end
  spec.bindir        = 'exe'
  spec.executables   = ['abide']
  spec.require_paths = ['lib']

  # Prod dependencies
  spec.add_dependency 'nokogiri', '~> 1.11'
  spec.add_dependency 'cmdparse', '~> 3.0'
  spec.add_dependency 'puppet', '>= 6.23'
  spec.add_dependency 'jira-ruby', '~> 2.2'
  spec.add_dependency 'ruby-progressbar', '~> 1.11'
  spec.add_dependency 'selenium-webdriver', '~> 4.0.0.beta4'
  spec.add_dependency 'google-cloud-storage', '~> 1.34'
  spec.add_dependency 'hashdiff', '~> 1.0'
  spec.add_dependency 'amatch', '~> 0.4'

  # Dev dependencies
  spec.add_development_dependency 'bundler'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'console'
  spec.add_development_dependency 'github_changelog_generator'
  spec.add_development_dependency 'gem-release'
  spec.add_development_dependency 'pry'
  spec.add_development_dependency 'rspec', '~> 3.10'
  spec.add_development_dependency 'rubocop', '~> 1.8'
  spec.add_development_dependency 'rubocop-rspec', '~> 2.1'
  spec.add_development_dependency 'rubocop-ast', '~> 1.4'
  spec.add_development_dependency 'rubocop-performance', '~> 1.9'
  spec.add_development_dependency 'rubocop-i18n', '~> 3.0'
  spec.add_development_dependency 'fast_gettext', '~> 1.8'

  # For more information and examples about making a new gem, checkout our
  # guide at: https://bundler.io/guides/creating_gem.html
end
