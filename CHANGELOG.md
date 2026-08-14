# Changelog

## 0.6.0

- Add `rails_spec_flaky_check`: runs a spec selection multiple times with
  independently random seeds (RSpec's `--seed` is equivalent to `--order
  rand:SEED`) and reports which examples' pass/fail status was
  inconsistent across runs -- separately from examples that failed every
  run (`consistently_failing`, not flaky) and examples that passed every
  run (omitted). Each round's seed is included in the response so a
  specific divergence can be reproduced with a plain `rails_spec_run`
  call. `rails_spec_run` itself is unchanged by this release.

## 0.5.2

- Fix `WorkerManager` getting permanently stuck treating a dead worker as
  alive: `Worker::Client#alive?` used `Process.kill(0, pid)`, which returns
  true for an unreaped zombie, and the one existing auto-restart-and-retry
  path only caught `Worker::Client::DisconnectedError`, not a raw
  `Errno::EPIPE`/`SystemCallError` from writing to a dead worker's pipe.
  Every call after a worker died this way failed identically, forever --
  since stdio MCP servers have no lighter reconnect in Claude Code, this
  previously required a full session restart to recover from.
- Add `rails_runtime_restart`: unconditionally tears down and respawns the
  test worker, for whatever the automatic detection above doesn't catch.
- Fix RSpec's own "(files took N seconds to load)" reporting growing
  across every `rails_spec_run` call made through the same warm,
  forked-per-run worker -- it was measuring time since the worker first
  booted, not time this run's files took to load, because `rspec-core`
  freezes that timestamp once per process and Coatepec never reset it on
  reuse.

## 0.5.1

- Fix `rails_model` crashing outright for a model with a `has_one`/
  `has_many :through` association that goes through a polymorphic
  `belongs_to` (e.g. `has_one :x, through: :notable, source: :y` where
  `belongs_to :notable, polymorphic: true`). `foreign_key` on that
  reflection needs a single fixed class to resolve, which a polymorphic
  association can't provide, and that was previously an unrescued
  `ArgumentError` that took down the whole response. That specific case now
  reports `foreign_key: nil`/`class_name: nil` for the affected association,
  the same way an already-handled plain polymorphic `belongs_to` does.
- Add a general safety net around each association's metadata: if a single
  association still fails for some other, not-yet-anticipated
  `ActiveRecord` reflection quirk, only that association's entry degrades
  (gaining an `error` field describing what went wrong) instead of the
  entire `rails_model` call crashing for the whole model.

## 0.5.0

- **Breaking:** `mcp` is no longer a runtime dependency of the `coatepec`
  gem -- it's a development dependency, since Coatepec is meant to be
  installed once outside any Rails app's own bundle and pointed at the app
  via `--root`, not added to the app's `Gemfile` (`Worker::Client` resolves
  the worker's `RUBYLIB` from Coatepec's own installation regardless).
  Anyone whose MCP config currently launches Coatepec with `bundle exec
  coatepec` from inside a target app's bundle will hit a `LoadError` on
  upgrade once that bundle no longer pulls in `mcp` transitively.

  **Migration:** `gem install mcp` alongside `coatepec`, and change your MCP
  client config to invoke `coatepec` directly rather than `bundle exec
  coatepec` (drop the `coatepec` line from the target app's `Gemfile` too,
  if present -- see the README Quickstart for the corrected install story).

## 0.4.1

- Fix `exe/coatepec-worker` booting against a target app whose locally
  installed default-gem versions (e.g. `json`) differ from what its
  `Gemfile.lock` pins: `require "bundler/setup"` now runs before
  `require "coatepec"` itself, so Bundler can pin default gems before
  Ruby auto-activates a newer locally installed version and locks it in
  for the rest of the process. Previously this broke every coatepec call
  against such an app with `already activated X, but your Gemfile
  requires Y`.

## 0.4.0

- Add `enums` to `rails_model`'s output, sourced from ActiveRecord's own
  `defined_enums` API (pure in-memory, no DB query, no eval). Attempted
  unconditionally, unlike `columns`/`associations`, since enum declarations
  don't need a real table.

## 0.3.0

- Add `rails_routes` and `rails_model` MCP tools: bounded, filterable route
  listing and ActiveRecord schema/association/validator introspection,
  both running synchronously in the existing warm test worker (no
  fork/spawn). `rails_model` is restricted to `ActiveRecord::Base`
  descendants, resolved only via `safe_constantize` against a validated
  constant-name pattern -- no eval, no arbitrary method dispatch.
- The warm worker now forces Rails' reload-checking on at boot (overriding
  the target app's own `test.rb`, which disables it by default) and wraps
  every dispatched command in `Rails.application.reloader.wrap`, so edited
  model files no longer serve stale metadata without a worker restart.
  Benefits `rails_runtime_status` and `rails_spec_run`'s fork path too.
  Note that this applies process-wide: `rails_spec_run` also executes specs
  under the forced `enable_reloading`/`cache_classes` settings rather than
  the app's own `test.rb` values. The file watcher is pinned to the polling
  `ActiveSupport::FileUpdateChecker` at the same time, so an app configuring
  `ActiveSupport::EventedFileUpdateChecker` doesn't get `listen` threads
  started inside the warm worker (and inside the fork guard's baseline).

## 0.2.0

- Add an opt-in, guarded `Process.fork` strategy for macOS
  (`macos_fork: true` in a project's `.coatepec.yml`), closing most of the
  warm-worker performance gap that previously only benefited Linux. Guards
  a live thread-count check and a loaded-gem denylist against fork-unsafety,
  and transparently falls back to a fresh spawn -- with the remaining
  timeout budget, and the crashed child's stderr for diagnosis -- if a
  guard fails or the forked child crashes. `rails_spec_run` results gain
  an `execution_mode` field when this strategy is in play.

## 0.1.0

- Initial implementation: `rails_spec_run` and `rails_runtime_status` MCP tools,
  a warm Rails test worker with fork (Linux) / spawn (macOS) isolation per
  RSpec run, and a path-selector allowlist as the security boundary.
