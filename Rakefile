# frozen_string_literal: true

require 'rake'
require "bundler/gem_tasks"
require "rspec/core/rake_task"

spec_task = RSpec::Core::RakeTask.new(:spec)
spec_task.pattern = 'spec/abide_dev_utils_spec.rb,spec/abide_dev_utils/**/*_spec.rb'

require "rubocop/rake_task"

RuboCop::RakeTask.new

task default: %i[spec rubocop]

MODULES = %w[puppetlabs-cem_linux puppetlabs-sce_linux puppetlabs-cem_windows puppetlabs-sce_windows].freeze

def modules_with_repos
  @modules_with_repos ||= MODULES.select do |mod|
    system("git ls-remote git@github.com:puppetlabs/#{mod}.git HEAD")
  end
end

namespace 'sce' do
  directory 'spec/fixtures'
  MODULES.each do |mod|
    directory "spec/fixtures/#{mod}" do
      sh "git clone git@github.com:puppetlabs/#{mod}.git spec/fixtures/#{mod}"
    end
  end

  task :fixture, [:sce_mod] do |_, args|
    mod_name = MODULES.find { |m| m.match?(/#{args.sce_mod}/) }
    raise "No fixture found matching #{args.sce_mod}" unless mod_name

    Rake::Task[mod_name].invoke
  end

  multitask fixtures: modules_with_repos.map { |m| "spec/fixtures/#{m}" } do
    puts "All fixtures are ready"
  end
end
