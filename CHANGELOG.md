# Changelog

## 0.8.0

- Tool responses are now compact JSON rather than pretty-printed (22-32%
  smaller on measured payloads); set `COATEPEC_PRETTY=1` on the server
  process to restore indentation.
- `rails_spec_run` and `rails_test_run` now omit passing examples from
  `examples` by default -- a 49-test green run drops from ~3,700 tokens to
  ~160 -- and `summary` gains `pending_count`. Pass the new
  `include_passing: true` input to get the full roster back (still capped at
  500 examples). `rails_spec_flaky_check` is unaffected: it still sees every
  example.
- `examples[].description` (and `flaky_examples[].description`) is omitted
  when it would only repeat `id`, which is always the case for Minitest.
- `rails_routes` and `rails_controller` now include the routes of engines
  mounted in the application, expanded one level deep (an engine mounted
  inside another engine stays an opaque mount route, the same boundary
  `bin/rails routes` draws). Paths carry the mount point, so
  `/widget_admin/audits(.:format)` is what both tools report, and a
  controller living inside an engine no longer has all of its actions listed
  under `unroutable_actions`.
- `rails_routes` items and `rails_controller`'s `actions[].routes` entries
  gain an `engine` field: `null` for an application route, the engine's class
  name otherwise. `rails_routes`' `query` matches against it like every other
  column, so `query: "Avo::Engine"` returns exactly that engine's routes.
  Application routes are listed before engine routes.
- An engine route's `name` (`route_name` in `rails_controller`) is relative
  to its engine: it is reached through the mount's helper,
  `<mount name>.<name>_path`, where the mount name is the `name` of the mount
  route itself -- never as a top-level url helper.
- `rails_routes` and `rails_controller` now omit routes Rails marks
  `internal` -- its own `/rails/info` and friends -- matching
  `bin/rails routes`. This is a behaviour change for callers that relied on
  seeing them.
- Add Minitest support to `rails_spec_run` and `rails_spec_flaky_check`:
  selectors under a `test/` root ending in `_test.rb` run through Rails'
  Minitest runner in the same warm worker, with the same
  `example`/`seed`/`fail_fast`/`timeout_seconds` inputs and the same result
  shape (`id` is `ClassName#test_method`; a skip is `"pending"`, an error is
  `"failed"`). The framework is chosen per call from the selector paths --
  an app that has both `spec/` and `test/` works without configuration; one
  call may not mix the two (`mixed_test_frameworks`).
- Add `rails_test_run` and `rails_test_flaky_check` as aliases of the two
  tools above, for agents that look for a Minitest-named tool. Identical
  schema and behaviour.
- The Minitest child sets `PARALLEL_WORKERS=1`, so a selection above Rails'
  parallelization threshold runs serially under the call's single timeout
  instead of forking a worker tree.
- `file:LINE` selection is implemented by Coatepec itself rather than relying
  on Rails' line filtering, which is absent in apps generated with
  `--skip-test` and targets a method Minitest 6 no longer calls on Rails 7.1.
- Path validation now runs before the framework is required, so an invalid
  path on a Minitest-only app reports `invalid_spec_path` instead of
  `unsupported_test_framework`. `invalid_spec_path` keeps its code for both
  frameworks.
- `rails_model` collapses validators with identical name, attributes and
  options into one entry (a concern and the model body declaring the same
  validation used to appear twice); the 200-item cap now counts distinct
  validators.
- `rails_routes` defaults to 100 items per page (was 50 -- engine expansion
  roughly doubled route counts) and returns `next_offset` for the follow-up
  call, `null` on the last page.
- `rails_spec_run`/`rails_test_run`: when several tests fail with the same
  error text (a broken layout erroring every controller test, say), `stdout`
  keeps the first failure block and replaces each repeat with one roll-up line
  naming the other tests -- a 5-error controller run drops from ~4,850 B to
  roughly a third of that. Backtrace frames and RSpec's `Failure/Error:`
  source line are ignored when deciding that two blocks match.
- `rails_spec_run`/`rails_test_run` gain `include_stdout` (default `true`).
  `include_stdout: false` returns `stdout: null` -- the key stays so the result
  shape is uniform -- for callers that only read `summary` and `examples`.
  `stderr` is always returned.

## 0.7.0

- Add `rails_controller`: reports an `ActionController` controller's
  actions, action callbacks, and included concerns. Admits
  `ActionController::API` controllers as well as `ActionController::Base`
  ones.
  - Each action is cross-referenced against `Rails.application.routes`,
    the same route table `rails_routes` reads: `actions[].routes` lists the
    verb/path/route name reaching that action (`path` is Rails' raw route
    spec, `(.:format)` suffix included, byte-identical to `rails_routes`'
    own `path` for the same route); `unroutable_actions` lists action
    methods no route reaches (probable dead code); `routes_without_action`
    lists route action names the controller doesn't define -- a request to
    one of those raises `AbstractController::ActionNotFound` in production,
    making this the tool's most actionable output.
  - `callbacks[]` reports each `before`/`after`/`around` filter's `only`/
    `except` action restriction (an array, or `nil` if unrestricted -- `nil`
    and `[]` are distinct and both preserved) and any remaining `if`/
    `unless` condition (a symbol by name; a Proc reported as `"(block)"`,
    never serialized directly, since `Proc#to_s` leaks the app's absolute
    source path).
  - `concerns` lists app-defined modules only, included directly or
    inherited from a base class; framework modules are excluded.
  - **Known limitations, both by design:** strong parameters
    (`params.require(...).permit(...)`) are not reported -- they exist only
    as code inside a method body, never as class metadata, and recovering
    them would require source parsing, which this gem does not do. Only the
    main app's route table is read, so a controller mounted inside an
    engine has its actions reported as unroutable even where the engine's
    own routes reach them -- the same boundary `rails_routes` already has.

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
