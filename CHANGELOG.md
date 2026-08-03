# Changelog

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
