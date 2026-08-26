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
