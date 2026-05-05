# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

`abide_dev_utils` is a Ruby gem that ships an `abide` CLI used by the Abide / Puppet SCE (Security Compliance Enforcement) team to develop compliance Puppet modules (CIS, STIG). The CLI converts XCCDF benchmarks into Hiera, generates mappings, builds coverage and reference reports against SCE modules, integrates with Jira, and (legacy) scrapes Puppet Comply.

The gem requires Ruby >= 2.7.0; CI runs on 3.2. The gem `puppet` is only installed when `PUPPET_AUTH_TOKEN` is set (it pulls from `rubygems-puppetcore.puppet.com`) — see `Gemfile`.

## Common commands

```sh
bin/setup                      # bundle install + initial setup
bundle exec rake               # default: spec + rubocop
bundle exec rake spec          # run all RSpec tests
bundle exec rspec spec/abide_dev_utils/sce/benchmark_spec.rb   # single file
bundle exec rspec spec/path/to_spec.rb:42                      # single example by line
bundle exec rubocop            # lint
bundle exec rake build         # build gem into pkg/
bundle exec rake install       # build + install locally
bin/console                    # IRB with the gem preloaded
bundle exec exe/abide -h       # run the CLI from a checkout
```

### SCE fixture modules (required for many specs)

Several specs and the coverage/reference generators load real Puppet modules from `spec/fixtures/`. Fetch them with:

```sh
bundle exec rake sce:fixtures             # clone all available fixture modules
bundle exec rake 'sce:fixture[linux]'     # clone a single fixture by partial name
```

The fixtures are cloned over SSH from `git@github.com:puppetlabs/<module>.git` (`puppetlabs-cem_linux`, `puppetlabs-sce_linux`, `puppetlabs-cem_windows`, `puppetlabs-sce_windows`). CI uses `webfactory/ssh-agent` with deploy keys; locally you need SSH access to those repos. Specs that require a fixture will fail if you skipped the clone.

`spec_helper.rb` exposes `sce_linux_fixture` / `sce_windows_fixture` helpers that prefer the `sce_*` repo and fall back to the older `cem_*` name.

## Architecture

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for a full breakdown of the file layout and architectural conventions.

## Release flow

`bundle exec rake release` builds the gem, tags the version in git, pushes, and pushes to rubygems.org. Bump `lib/abide_dev_utils/version.rb` first.
