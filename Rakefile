# frozen_string_literal: true

require 'rake'
require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "rubocop/rake_task"

RuboCop::RakeTask.new

task default: %i[spec rubocop]

namespace 'cem' do
  directory 'spec/fixtures'

  directory 'spec/fixtures/puppetlabs-cem_linux' do
    sh 'git clone git@github.com:puppetlabs/puppetlabs-cem_linux.git spec/fixtures/puppetlabs-cem_linux'
  end
  file 'spec/fixtures/puppetlabs-cem_linux' => ['spec/fixtures']

  directory 'spec/fixtures/puppetlabs-cem_windows' do
    sh 'git clone git@github.com:puppetlabs/puppetlabs-cem_windows.git spec/fixtures/puppetlabs-cem_windows'
  end
  file 'spec/fixtures/puppetlabs-cem_windows' => ['spec/fixtures']

  task :fixture, [:cem_mod] do |_, args|
    case args.cem_mod
    when /linux/
      Rake::Task['spec/fixtures/puppetlabs-cem_linux'].invoke
    when /windows/
      Rake::Task['spec/fixtures/puppetlabs-cem_windows'].invoke
    else
      raise "Unknown CEM module #{args.cem_mod}"
    end
  end

  multitask fixtures: %w[spec/fixtures/puppetlabs-cem_linux spec/fixtures/puppetlabs-cem_windows]
end
