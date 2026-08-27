# Roadmap

Ideas and known future work for Coatepec, roughly in the order they came up.
Nothing here is committed to a release; this is a place to write things down
before they're designed, not a promise.

## Minitest support

Every current tool (`rails_spec_run`, `rails_spec_flaky_check`, and the
paused `rails_spec_profile` below) is built around RSpec: `Coatepec::Spec::Runner`
shells out to `bundle exec rspec`/forks an RSpec process, and
`Coatepec::Spec::PathPolicy` validates selectors against RSpec's own
`*_spec.rb` convention. None of that carries over to a Rails app using
Minitest instead.

The shape of the fix should mirror what already exists rather than
invent something new: a parallel `Coatepec::Minitest::Runner` (or
similarly named) implementing the same "validate selectors, build CLI
args, run via the platform strategy, return a structured result" contract
`Spec::Runner` already does, reusing `ForkStrategy`/`SpawnStrategy`/`GuardedForkStrategy`
as-is where their logic is genuinely test-framework-agnostic (they mostly
just fork/spawn a command and reap it — the RSpec-specific parts are
`Runner#build_args` and the `--format json` output parsing in
`Coatepec::Spec::Result`, both of which would need Minitest equivalents:
Minitest's own JSON/machine-readable reporter, or `minitest-reporters`
gem output, would need to be identified before designing that half).

**Framework auto-detection via the Gemfile is straightforward and doesn't
need new machinery** — `Coatepec::Worker::RailsRuntime#loaded_gem_names`
already exists and is exactly the mechanism `GuardedForkStrategy` uses
today to check for fork-unsafe gems, and `Coatepec::Spec::FactoryProfRunner`
(see below) uses to check for `test-prof`. The same `loaded_gem_names.include?("rspec-rails")`
vs. `.include?("minitest")` check (a Rails app's default `Gemfile` already
declares one or the other, sometimes both) is enough to route
`rails_spec_run` (or a to-be-decided `rails_test_run`, if the two
frameworks' capabilities diverge enough to warrant separate tool names
rather than one dispatching tool) to the right runner. `Coatepec::Spec::Runner#require_rspec!`
already anticipates the gap in spirit: it raises `:unsupported_test_framework`
today when `rspec-rails` isn't loadable, rather than assuming RSpec
unconditionally.

Open questions for whenever this gets designed properly:
- One tool name that dispatches by detected framework, or separate
  `rails_spec_run`/`rails_minitest_run`-style tools? (Affects whether an
  agent needs to know which framework a given app uses before calling the
  right tool, vs. the tool figuring it out.)
- What Minitest gives you for structured per-example output
  (pass/fail/pending, id, file/line) equivalent to RSpec's `--format json`
  — needed before `rails_spec_flaky_check`'s per-example flaky-detection
  logic (`Coatepec::Spec::FlakyChecker`, framework-agnostic in principle
  since it only depends on `Runner#run`'s result shape) could target
  Minitest too.
- Whether Minitest's own `--seed` (it has one; Minitest randomizes test
  order by default too) is enough of an equivalent to RSpec's `--seed`
  for `rails_spec_flaky_check` to reuse the same "rerun N times with a
  fresh random seed" mechanism unchanged.

## Get stats on a spec/test run (TestProf / FactoryProf) — designed, implemented, paused

The general idea: a tool that runs a spec selection and comes back with
more than pass/fail — profiling data about the run itself (factory
creation counts/timing being the concrete first target, via
[TestProf](https://test-prof.evilmartians.io/)'s FactoryProf profiler,
which is the one TestProf profiler with real structured JSON output;
others like EventProf are text-only and out of scope for now).

A `rails_spec_profile` tool (runs a spec with TestProf's FactoryProf
enabled, returning factory usage stats alongside normal pass/fail data)
was fully designed and implemented, but paused before merging: TestProf's
`FPROF` env var only activates at Ruby's `require` time, not at RSpec-run
time as originally assumed, which makes it silently a no-op on
`ForkStrategy` (Linux's default) — confirmed empirically, not just
inferred. See `docs/superpowers/specs/2026-08-13-factory-prof-tool-design.md`
(local-only, not committed — see that repo's `.gitignore`) for the full
root-cause writeup and the fix options considered (forcing `SpawnStrategy`
for profiled runs specifically, vs. detecting and raising a clear error on
non-spawn strategies, vs. a Linux-only opt-out config knob). Paused
specifically to wait for real signal on how coatepec is actually used
(Linux vs. macOS, `macos_fork` adoption) before picking a fix, rather than
guessing.

## Run Rails 8.1's built-in CI (`bin/ci`)

Rails 8.1 introduced `ActiveSupport::ContinuousIntegration`
(`activesupport/lib/active_support/continuous_integration.rb`) as the
engine behind a generated `bin/ci`/`config/ci.rb`: a small DSL (`step`,
`group`) that a new app's `config/ci.rb` uses to declare, by default,
`bin/setup`, `bin/rubocop`, `bin/bundler-audit`, `bin/importmap audit`
(if using importmap), `bin/brakeman --quiet --no-pager --exit-on-warn
--exit-on-error`, and the test suite -- the same steps the generated
GitHub Actions workflow runs, since that workflow just calls `bin/ci`.
A coatepec tool that ran this and reported back which steps
passed/failed would cover security audits (Brakeman, bundler-audit,
importmap audit) and style checks in one call, for any app that has
adopted this (Rails 8.1+ only -- confirmed against the actual generator
template and `ContinuousIntegration` source, not a blog summary).

**The real design obstacle, found while researching this (not yet
solved):** `ContinuousIntegration` has no structured output at all. Each
`step` runs via plain `system(*command)` and writes colorized terminal
text (`✅ Title passed in 1.2s` / `❌ Title failed in 1.2s`); the only
machine-readable signal is the overall process exit code
(`abort unless success?`). Two options for whenever this gets designed:
scrape that text (fragile -- it's an internal, unversioned Rails string
format, not a documented API), or require the target app's `config/ci.rb`
in-process and read `ContinuousIntegration#results` (an array of
`[success, title]` pairs) directly, intercepting the `abort` that
normally follows a failure -- more work, but reads real data instead of
parsing text designed for a terminal.

Also worth deciding: whether this becomes its own tool (`rails_ci_run`?)
or folds into an existing one, and whether "security audits" specifically
(Brakeman/bundler-audit/importmap audit, independent of the rest of
`bin/ci`) are worth exposing as a narrower, separate tool for apps that
don't use Rails 8.1's `bin/ci` scaffold at all but do have those gems.

## Controller introspection

A `rails_controller`-style tool mirroring the existing `rails_model`
(`Coatepec::Introspection::Model`) and `rails_routes`
(`Coatepec::Introspection::Routes`) tools' shape: given a controller
constant, return its actions, `before_action`/`around_action`/`after_action`
filters (and which actions they apply to), strong-parameter method
definitions, and included concerns -- via real Rails introspection APIs
(`ActionController::Base` callback chains, not source parsing), the same
trust boundary `rails_model` already holds to.

## Background job introspection -- built, then parked (PR #14, closed unmerged)

The original idea: a `rails_job`-style tool for `ActiveJob` classes --
queue name, retry/discard configuration, and callbacks -- following the
same bounded, read-only, real-API-not-source-parsing pattern as
`rails_model`, since coatepec has no visibility into background jobs at
all today.

It was fully built and reviewed as `rails_job`
(`Coatepec::Introspection::Job`), then **closed unmerged** in
[PR #14](https://github.com/mogox/coatepec/pull/14) -- the diff and its
review history stay there, so nothing needs re-deriving if this is picked
back up.

**Why it was parked:** the tool only sees `ActiveJob::Base` subclasses.
That's not an implementation shortcut -- it's the trust boundary doing its
job: the whole design reads real Rails introspection APIs
(`_perform_callbacks`, `rescue_handlers`, the `queue_name`/`priority` class
attributes) rather than parsing source, and those APIs exist only on
ActiveJob. An app whose jobs are native Sidekiq (`include Sidekiq::Job`)
or Delayed::Job classes gets `:not_active_job` and nothing else, because
those classes genuinely aren't ActiveJob jobs. (Sidekiq used *as the
ActiveJob queue adapter* is fine -- those jobs still subclass
`ApplicationJob`; it's hand-written Sidekiq/delayed_job worker classes
that fall outside.) Covering them would mean a second, adapter-specific
introspection path per backend -- `sidekiq_options` for retry/queue/dead,
`Delayed::Worker` config and `handle_asynchronously` for delayed_job --
which is a materially bigger design than the ActiveJob one, not a small
extension of it. Given a limited number of iterations to spend, that
budget goes to features usable across more real apps first.

Two constraints worth keeping if this is revisited:
- Even within ActiveJob, `retry_on` / `discard_on` / plain `rescue_from`
  are indistinguishable, and neither macro's `wait:`/`attempts:`/`queue:`/
  `priority:` options are introspectable -- ActiveJob closes over them
  inside a Proc rather than storing them as class metadata. Only the
  *list* of rescued exception classes is genuinely queryable.
- `queue_as { ... }` and `queue_with_priority { ... }` store unevaluated
  app blocks. Reading them naively either executes app code at
  introspection time or leaks the app's absolute source paths through
  `Proc#to_s`. PR #14 has the fix for both; any future version needs the
  same care.

## Cross-file consistency validation

Distinct from anything coatepec does today: a tool that checks for drift
*across* files rather than introspecting one thing at a time -- a route
pointing at a controller action that doesn't exist, a `belongs_to`/`has_many`
referencing a column or table that isn't in the schema, that kind of thing.
Surfaced while researching prior art (a competing tool does this via
source-code parsing); would need its own design for how to do it via
structured Rails APIs instead, consistent with how every other coatepec
tool avoids parsing source directly.

## Considered and set aside

- **Environment variable / credentials discovery** (a prior-art tool
  exposes this). Cuts directly against coatepec's "no credential access"
  security boundary -- not a fit regardless of usefulness.
- **AST-based code pattern analysis** (concerns, callbacks, service
  objects, helper methods, by parsing source rather than calling real
  Rails APIs). A meaningfully different, heavier, more fragile approach
  than every existing coatepec tool takes. Not ruled out forever, but a
  clear departure from the project's current trust model, not a natural
  extension of it.
- **Rails dev server lifecycle management** (start/stop/monitor `rails s`
  via MCP -- a different tool in the ecosystem does exactly this). A
  different category of feature (process lifecycle, not test/introspection)
  from everything else on this list; noted here for completeness, not
  actively being considered.
