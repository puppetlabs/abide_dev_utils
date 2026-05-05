# Architecture

This document describes the file/directory layout of `abide_dev_utils` so contributors and AI assistants can find the right place to make a change. For build/test commands, see `CLAUDE.md` and `README.md`.

`abide_dev_utils` is a developer helper for the **`puppetlabs-sce_linux`** and **`puppetlabs-sce_windows`** Puppet SCE modules. Most of the design choices in this repo (the `sce/` subsystem, the fixture-cloning rake task, the local fact sets in `files/`) exist to support those two modules, so when something in the architecture seems oddly specific, it's almost always because one of those modules needed it.

## Top-level layout

```
abide_dev_utils/
├── exe/                 ← gem-installed CLI binary
├── bin/                 ← in-repo dev binaries + setup script
├── lib/                 ← all library + CLI code (see lib/ section below)
├── spec/                ← RSpec tests, mirroring lib/ layout
├── files/               ← static resources shipped with the gem
├── docs/                ← contributor-facing docs (this file lives here)
├── pkg/                 ← rake build output (.gem files); not committed source
├── Gemfile / .gemspec   ← dependency + gem metadata
├── Rakefile             ← spec/rubocop/build tasks + sce:fixtures clone task
├── new_diff.rb          ← ad-hoc one-off script (not wired into the CLI)
└── README.md / CHANGELOG.md / LICENSE.txt / CODEOWNERS
```

The unusual ones:

- **`exe/abide`** is the Bundler-recommended location for installed binaries; `spec.executables = ['abide']` in the gemspec wires it up.
- **`bin/abide.rb`** is a duplicate entry point used during development so you can `ruby bin/abide.rb ...` without installing the gem. `bin/console` is an IRB session with the gem preloaded; `bin/setup` is the `bundle install` bootstrap.
- **`new_diff.rb`** is a developer scratch script that exercises the XCCDF diff code; it's not part of the public CLI surface.
- **`pkg/`** is rake build output. Don't edit anything in there.
- **`files/fact_sets/`** holds locally-stored fact sets used as a FacterDB fallback. `abide sce generate reference` (the `REFERENCE.md` generator) relies on the `facterdb` gem to look up facts for every OS that `sce_linux` / `sce_windows` declare in their `metadata.json`. When one of those modules adds support for a brand-new OS release, FacterDB doesn't always have a matching fact set yet — in that case we drop a `<os>-<version>-<arch>.facts` file (e.g. `windows-2025-x86_64.facts`) into `files/fact_sets/` and `ppt/facter_utils.rb` loads it instead. Once FacterDB ships the fact set upstream, the file here can be removed.

## `lib/abide_dev_utils/` — library + CLI

The whole gem lives under one namespace. `lib/abide_dev_utils.rb` is the require-everything entry point; the rest of the structure pairs each top-level CLI namespace with a sibling library directory.

```
lib/abide_dev_utils.rb              ← top-level require: pulls in every domain
lib/abide_dev_utils/
├── cli.rb                          ← cmdparse setup; registers the 6 top-level commands
├── cli/                            ← one file per top-level CLI namespace
│
├── sce.rb        sce/              ← `abide sce ...` library
├── xccdf.rb      xccdf/            ← `abide xccdf ...` library
├── ppt.rb        ppt/              ← `abide puppet ...` library + shared Puppet helpers
├── jira.rb       jira/             ← `abide jira ...` library
├── comply.rb                       ← `abide comply ...` library (deprecated, no subdir)
│
├── config.rb                       ← reads ~/.abide_dev.yaml
├── files.rb                        ← Reader/Writer dispatching on extension
├── output.rb                       ← simple/text/json/yaml/progress writers
├── validate.rb                     ← file/directory/hashable/puppet_module_directory checks
├── prompt.rb                       ← interactive y/n prompt used by jira flows
├── markdown.rb                     ← tiny Markdown builder used by sce reference generator
├── gcloud.rb                       ← google-cloud-storage wrapper (loaded but unused by CLI)
├── puppet_strings.rb               ← shared puppet-strings helpers
├── mixins.rb                       ← misc reusable mixins
├── dot_number_comparable.rb        ← <=> for dotted CIS ids ("1.2.10" > "1.2.2")
├── constants.rb                    ← CliConstants
├── version.rb                      ← VERSION string (bump before `rake release`)
│
├── errors.rb     errors/           ← typed exception classes, namespaced per domain
└── resources/                      ← ERB templates shipped with the gem (e.g. generic_spec.erb)
```

### `cli/` — CLI command classes

One file per top-level `abide <namespace>` command. Each file defines a `*Command` class plus its subcommands.

```
cli/
├── abstract.rb     ← AbideCommand base class (handles [DEPRECATED] tagging, mixes in Config)
├── sce.rb          ← `abide sce {generate,update-config,validate} ...`
├── xccdf.rb        ← `abide xccdf {to_hiera,diff,gen-map}`
├── puppet.rb       ← `abide puppet {coverage,new,...}`
├── jira.rb         ← `abide jira {auth,from_coverage,from_xccdf,new_issue,get_issue}`
├── comply.rb       ← `abide comply report` (DEPRECATED)
└── test.rb         ← `abide test` (DEPRECATED, currently broken)
```

All command classes inherit from `Abide::CLI::AbideCommand` (defined in `cli/abstract.rb`), which wraps `CmdParse::Command`, mixes in `AbideDevUtils::Config`, and prefixes short/long descriptions with `[DEPRECATED]` when `deprecated: true` is passed. Don't subclass `CmdParse::Command` directly when adding new commands.

### `sce/` — Security Compliance Enforcement domain

The largest subsystem. Operates on Puppet SCE modules on disk (`puppetlabs-sce_linux`, `puppetlabs-sce_windows`, etc.) and produces coverage reports, reference docs, and validation output.

```
sce.rb                                ← top-level entry; defines update_legacy_config_from_diff
sce/
├── benchmark_loader.rb               ← walks a Puppet module's supported_os × frameworks
│                                       and constructs Benchmark objects (errors are
│                                       collected, not raised)
├── benchmark.rb                      ← Benchmark / Resource / Control domain model
│                                       (Control mixes in DotNumberComparable)
│
├── generate.rb     generate/         ← `abide sce generate ...`
│   ├── coverage_report.rb            ← coverage-report subcommand
│   └── reference.rb                  ← reference (REFERENCE.md) subcommand
│
├── validate.rb     validate/         ← `abide sce validate ...`
│   ├── resource_data.rb              ← validates data/resource_data/*.yaml
│   ├── strings.rb                    ← runs puppet-strings over the module
│   └── strings/                      ← per-Puppet-type validators
│       ├── base_validator.rb
│       ├── puppet_class_validator.rb
│       ├── puppet_defined_type_validator.rb
│       └── validation_finding.rb
│
├── mapping/                          ← id ↔ id mapping (control numbers, hiera titles, ...)
│   └── mapper.rb                     ← Mapper, MapData, ALL_TYPES / FRAMEWORK_TYPES enums
│
└── hiera_data.rb   hiera_data/       ← parsing the SCE module's data/ directory
    ├── mapping_data.rb               ← entry point for data/mapping/*.yaml
    ├── mapping_data/
    │   ├── map_data.rb               ← parses one mapping YAML file
    │   └── mixins.rb                 ← MixinCIS / MixinSTIG (per-framework lookup logic)
    └── resource_data/                ← (placeholder; reserved for resource_data parsers)
```

`sce.rb` plus everything in `sce/` is what powers the `abide sce` CLI. The pattern of *"top-level `.rb` requires the subdirectory"* is consistent across the codebase — `sce/generate.rb` requires `sce/generate/*.rb`, and so on.

### `xccdf/` — XCCDF parsing and conversion

```
xccdf.rb                              ← entry points (gen_map, to_hiera, diff) +
│                                       XCCDF::Common (CIS/STIG regex constants) +
│                                       XCCDF::Benchmark
xccdf/
├── parser.rb       parser/           ← Nokogiri-based parser
│   ├── helpers.rb
│   └── objects.rb  objects/
│       ├── numbered_object.rb        ← controls/profiles with dotted numbers
│       └── diffable_object.rb        ← objects participating in benchmark diffing
│
├── diff.rb                           ← BenchmarkDiff (used by `abide xccdf diff` and the
│                                       currently-disabled `sce update-config from-diff`)
└── utils.rb                          ← shared XCCDF helpers
```

`XCCDF::Common` (in `xccdf.rb`) is the **single source of truth** for CIS vs STIG conventions: control-id regexes, profile-level codes, the `normalize_string` / `normalize_control_name` / `normalize_profile_name` helpers that the README documents. Touching the constants in `Common` affects mapping generation, Hiera key naming, and diffing simultaneously.

### `ppt/` — Puppet-module utilities

Used both by the `sce/` subsystem (to read manifests off disk) and directly by the `abide puppet ...` commands.

```
ppt.rb                                ← top-level helpers: rename_puppet_class, build_new_object,
│                                       audit/fix_class_names, add_cis_comment, score_module
ppt/
├── puppet_module.rb                  ← PuppetModule class: reads metadata.json, hiera.yaml;
│                                       exposes supported_os used by BenchmarkLoader
├── class_utils.rb                    ← Puppet class name ↔ on-disk path conversions
├── code_introspection.rb             ← parses Puppet manifests (used by Resource.manifest)
├── hiera.rb                          ← Hiera::Config wrapper for a module's hiera.yaml
├── facter_utils.rb                   ← FacterDB integration; can also load files/fact_sets/*.facts
├── strings.rb                        ← puppet-strings helpers
├── api.rb                            ← misc Puppet API glue
├── new_obj.rb                        ← `abide puppet new` ERB-based generator
│                                       (honours c-/d- filename prefixes for spec dir routing)
├── score_module.rb                   ← stub; Ppt.score_module currently prints "not implemented"
│
└── code_gen.rb     code_gen/         ← AST-style wrappers for code generation
    ├── generate.rb
    ├── data_types.rb
    ├── resource.rb
    ├── resource_types.rb
    └── resource_types/
        ├── base.rb
        ├── class.rb
        ├── manifest.rb
        ├── parameter.rb
        └── strings.rb
```

### `jira/` — Jira integration

```
jira.rb                               ← top-level flows: new_issues_from_coverage,
│                                       new_issues_from_xccdf, summary helpers.
│                                       Defines summary prefixes (COV_PARENT_SUMMARY_PREFIX,
│                                       COV_CHILD_SUMMARY_PREFIX, UPD_EPIC_SUMMARY_PREFIX)
│                                       used to recognise issues this tool created.
jira/
├── client.rb                         ← jira-ruby client wrapper
├── client_builder.rb                 ← builds a client from ~/.abide_dev.yaml's jira section
├── dry_run.rb                        ← drop-in replacement returned when --dry-run is set
├── finder.rb                         ← search existing issues
├── issue_builder.rb                  ← payload construction for create/update
└── helper.rb                         ← project-level convenience (all_project_issues_attrs, etc.)
```

### `errors/` — typed exceptions

```
errors.rb                             ← requires the per-domain files
errors/
├── base.rb                           ← AbideDevUtils::Errors::* base class
├── general.rb                        ← cross-cutting errors (FileNotFoundError, etc.)
├── sce.rb                            ← BenchmarkLoadError (carries osname, major_version,
│                                       framework, module_name, original_error fields that
│                                       cli/sce.rb pretty-prints via respond_to?)
├── xccdf.rb                          ← UnsupportedXCCDFError, ProfilePartsError, ControlPartsError
├── ppt.rb                            ← Puppet-module errors (ClassFileNotFoundError, ...)
├── jira.rb                           ← Jira-specific errors
├── comply.rb                         ← Comply scraper errors (deprecated)
└── gcloud.rb                         ← GCS errors
```

When introducing a new "soft" error that the CLI should pretty-print rather than raise, follow the `BenchmarkLoadError` pattern: subclass the matching domain error and expose extra metadata as accessors. The CLI uses `respond_to?` to decide which fields to render.

### `comply.rb` — deprecated Selenium scraper

A single file (no `comply/` subdirectory) that drives `selenium-webdriver` against the Puppet Comply UI. It's deprecated and still loaded mostly so the deprecation message stays visible. Don't extend it.

## `spec/` — tests

The spec layout mirrors `lib/abide_dev_utils/`:

```
spec/
├── spec_helper.rb                    ← requires every file under lib/ (catches load-order
│                                       regressions); exposes TestResources / OutputHelpers
├── abide_dev_utils_spec.rb           ← top-level smoke tests
├── abide_dev_utils/                  ← mirrors lib/abide_dev_utils/ one-to-one
│   ├── cli_spec.rb
│   ├── xccdf_spec.rb
│   ├── xccdf/
│   │   ├── parser_spec.rb
│   │   ├── parser/objects_spec.rb
│   │   └── diff/benchmark_spec.rb
│   ├── sce/benchmark_spec.rb
│   └── ppt/
│       ├── facter_utils_spec.rb
│       └── new_obj_spec.rb
│
├── resources/                        ← committed test inputs (work without network)
│   ├── cis/                          ← real CIS XCCDF files for parser tests
│   │   ├── CIS_CentOS_Linux_7_Benchmark_v3.0.0-xccdf.xml
│   │   └── CIS_Microsoft_Windows_Server_2016_..._v1.2.0-xccdf.xml
│   └── test_files/                   ← small synthetic XCCDFs for diff/version tests
│       ├── Test_XCCDF-v1.0.0-xccdf.xml
│       └── Test_XCCDF-v1.1.0-xccdf.xml
│
└── fixtures/                         ← real Puppet SCE modules cloned at test time by
                                        `rake sce:fixtures`. Not committed; required by
                                        any spec that exercises BenchmarkLoader.
    ├── puppetlabs-sce_linux/         ← clone of git@github.com:puppetlabs/puppetlabs-sce_linux
    └── puppetlabs-sce_windows/       ← clone of git@github.com:puppetlabs/puppetlabs-sce_windows
```

`spec_helper.rb` exposes helpers via mixins: `sce_linux_fixture` / `sce_windows_fixture` (prefer the `sce_*` clone, fall back to `cem_*`), `test_xccdf_files`, `capture_stdout`, `capture_stderr`. RSpec is configured with `disable_monkey_patching!`, `verify_partial_doubles = true`, and `fail_fast = false` — keep partial doubles realistic.

## How a request flows through the codebase

Tracing `abide sce generate coverage-report` end-to-end is a good way to internalise the layout:

1. **`exe/abide`** loads `lib/abide_dev_utils/cli.rb` and calls `Abide::CLI.execute`.
2. **`cli.rb`** registers `SceCommand` (from `cli/sce.rb`) on the cmdparse parser.
3. **`cli/sce.rb`** routes `generate coverage-report` to `SceGenerateCoverageReport#execute`, which collects flags into `@data` and calls `AbideDevUtils::Sce::Generate::CoverageReport.generate(...)`.
4. **`sce/generate/coverage_report.rb`** asks `BenchmarkLoader::PupMod` (in `sce/benchmark_loader.rb`) to load benchmarks from the current directory.
5. **`benchmark_loader.rb`** instantiates a `Ppt::PuppetModule` (from `ppt/puppet_module.rb`), reads `metadata.json` for `supported_os`, and constructs one `Sce::Benchmark` per (OS, version, framework) cell.
6. Each **`Sce::Benchmark`** (in `sce/benchmark.rb`) builds a `Mapping::Mapper` (from `sce/mapping/mapper.rb`) over the module's `data/mapping/*.yaml` files, and a list of `Resource` objects whose manifests are parsed by `Ppt::CodeIntrospection::Manifest` (from `ppt/code_introspection.rb`).
7. The coverage report is serialised through **`output.rb`** as YAML/JSON/text, optionally written to a file via **`files.rb`**'s `Writer`.

Every other command follows the same shape: `cli/<name>.rb` parses options → top-level domain module orchestrates → domain classes do the work → `Output` writes the result.
