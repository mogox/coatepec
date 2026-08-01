# Changelog

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
