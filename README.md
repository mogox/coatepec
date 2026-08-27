# Coatepec

Coatepec gives coding agents a bounded way to run targeted RSpec examples
against a Rails application, over MCP, without exposing a general Rails
console.

## Quickstart

Coatepec is installed once, outside of any Rails app's own bundle, and
points at the app via `--root`:

```bash
gem install coatepec mcp
coatepec --version
```

Do not add `coatepec` to the target app's `Gemfile`. `Worker::Client#spawn_worker`
resolves both the worker executable and its `RUBYLIB` from Coatepec's own
installation, not from the app's bundle -- so the worker gets Coatepec's
`lib` regardless of what the app's Gemfile says. Adding it there is not just
redundant, it's a version-skew hazard: Bundler would activate whatever
version is in the app's lockfile while Coatepec itself keeps running the
version on `RUBYLIB`, and a drift between the two surfaces as a confusing
"already activated" failure. The only thing Coatepec needs from the target
app is `railties`, which is definitionally present in any Rails app you'd
point it at. Host app footprint is zero: no Gemfile line, no lockfile
change, no dependency resolution.

With the [Claude Code CLI](https://docs.claude.com/en/docs/claude-code),
from the Rails app's own root:

```bash
claude mcp add coatepec --scope project -- coatepec --root .
```

That writes a project-scoped `.mcp.json` you can commit so the whole team
gets it. For any other MCP-compatible client, or to write it by hand, the
same thing looks like:

```json
{
  "mcpServers": {
    "coatepec": {
      "command": "coatepec",
      "args": ["--root", "."]
    }
  }
}
```

## Architecture

```text
MCP client
    |
    | JSON-RPC over stdio
    v
Coatepec parent (Rails-free)
    `-- private NDJSON --> test worker (Rails "test", booted lazily, kept warm)
                              |-- Linux:  Process.fork  --> isolated RSpec child
                              `-- macOS:  Process.spawn --> fresh RSpec process (default)
                                          Process.fork, guarded --> opt-in, see Configuration
```

## Configuration

An optional `.coatepec.yml` at the target Rails app's root enables
per-project settings:

```yaml
macos_fork: true                     # opt into forking on macOS (see below)
macos_fork_unsafe_gems: [some_gem]   # extends the built-in fork-unsafe denylist
```

A missing file means every setting takes its default -- this file is never
required.

### macOS fork (experimental, opt-in)

On macOS, `rails_spec_run` normally spawns a fresh `bundle exec rspec`
process per call, re-booting Rails every time -- the warm-worker speedup
described above only applies on Linux by default. Setting `macos_fork:
true` lets Coatepec attempt `Process.fork` on macOS too, reusing the warm
boot the way Linux does.

This is opt-in because forking a process with native extensions loaded
isn't universally safe. Before each fork, Coatepec checks the worker's
live thread count against its post-boot baseline and its loaded gems
against a denylist, falling back to a fresh spawn for that one call if
either check looks risky. The built-in denylist ships empty -- no single
gem has been confirmed as the culprit yet -- so the guard is effectively
thread-count-only until a project adds its own
`macos_fork_unsafe_gems`. If a fork is attempted and the child crashes
anyway, Coatepec transparently retries via spawn and returns that result
-- fork stays enabled for later calls. Every `rails_spec_run` result
includes an `execution_mode` field (`fork`, `spawn_fallback`, or
`spawn_after_crash`) so you can see which path actually ran for a given
call; `spawn_after_crash` results also carry the crashed fork's own stderr
under `crashed_fork_stderr` so the crash can be diagnosed.

`macos_fork: true` also effectively requires
`OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES` in Coatepec's own environment.
Without it, a forked child that touches an Objective-C-initialized class
aborts -- Coatepec retries via spawn, so it degrades silently to the slow
path (no crash, no error surfaced) rather than failing loudly, and you
simply never get the speedup. Set it on the MCP server process itself:

```json
{
  "mcpServers": {
    "coatepec": {
      "command": "coatepec",
      "args": ["--root", "."],
      "env": { "OBJC_DISABLE_INITIALIZE_FORK_SAFETY": "YES" }
    }
  }
}
```

Be aware this flag disables a real safety check in Apple's Objective-C
runtime; it's a reasonable trade for a local dev/test sidecar, but it's not
a no-op.

## Tools

| Tool | Input | Notes |
|---|---|---|
| `rails_spec_run` | `paths: string[1..100]`, `example?`, `seed?`, `fail_fast?`, `timeout_seconds?` (1..900, default 120) | Isolated per run; output capped at 256 KiB per stream |
| `rails_runtime_status` | `{}` | Reports Ruby/Rails versions, worker PID, boot_id, lifecycle state |
| `rails_runtime_restart` | `{}` | Unconditionally respawns the worker, discarding its warm boot |
| `rails_routes` | `query?`, `limit?` (1..200, default 50), `offset?` | Case-insensitive filter across name/verb/path/controller/action |
| `rails_model` | `name` (constant path, e.g. `Widget` or `Admin::Widget`) | ActiveRecord models only; columns, associations, validators, enums -- no row data |
| `rails_job` | `name` (constant path, e.g. `SendMailJob` or `Admin::SendMailJob`) | ActiveJob classes only; queue name/priority, perform callbacks, rescued exception classes -- no enqueuing, no execution |
| `rails_spec_flaky_check` | `paths`, `example?`, `timeout_seconds?` (per round, 1..900), `runs?` (2..20, default 5) | Runs the selection `runs` times with a fresh random seed each round; reports examples whose status was inconsistent across runs |

### Example queries

`rails_routes`:

- "What are all the routes in this app?" -- `rails_routes()`
- "What's the URL for widgets?" -- `rails_routes(query: "widget")`. `query` is a
  case-insensitive substring match across name, verb, path, controller, *and*
  action -- not just the path -- so a resource name alone typically returns
  every route for that resource (index/create/new/...); narrow further with
  something like `query: "new_widget"` to hit one route by name.
- "Which routes accept POST?" -- `rails_routes(query: "POST")`, the same
  substring match applied to the verb column.

`rails_model`:

- "What columns does Widget have, and which are nullable?" --
  `rails_model(name: "Widget")` -- see `columns[].null`, `columns[].sql_type`,
  `columns[].default`.
- "What validations and associations does Widget enforce?" -- same call --
  see `validators` and `associations`.
- "What happens if I ask about a non-model class, like a controller?" --
  `rails_model(name: "ApplicationController")` raises `not_active_record_model`
  rather than introspecting it (a nonexistent constant raises `model_not_found`
  instead) -- the tool only ever reflects on `ActiveRecord::Base` descendants.

`rails_job`:

- "What queue does WidgetIndexJob run on, and at what priority?" --
  `rails_job(name: "WidgetIndexJob")` -- see `queue_name`, `queue_priority`.
- "Does this job retry or discard on any particular exception?" -- same call --
  see `rescued_exceptions`. This is a bare list of exception class names with
  *some* handler registered (`retry_on`, `discard_on`, or a plain
  `rescue_from` all look the same from outside) -- it cannot show which macro
  registered a given exception, or its `wait:`/`attempts:`/`queue:`/
  `priority:` options, since those are closed over inside the handler itself
  rather than stored as separate, introspectable class metadata.
- "What if the job's queue name or priority is computed dynamically?" --
  a job that calls `queue_as { ... }` or `queue_with_priority { ... }` (the
  block forms) reports `queue_name: "(dynamic)"` / `queue_priority:
  "(block)"` rather than evaluating the block -- `rails_job` never executes
  app code to compute the real value.
- "What happens if I ask about a non-job class, like a model?" --
  `rails_job(name: "Widget")` raises `not_active_job` rather than
  introspecting it (a nonexistent constant raises `job_not_found` instead) --
  the tool only ever reflects on `ActiveJob::Base` descendants.

`rails_spec_flaky_check`:

- "Is this spec flaky?" -- `rails_spec_flaky_check(paths: ["spec/models/widget_spec.rb"])`
  runs it 5 times (default), each with an independently random seed
  (equivalent to RSpec's `--order rand:SEED`), and reports any example
  whose pass/fail status wasn't the same every time under `flaky_examples`
  -- distinct from `consistently_failing` (fails every run: broken, not
  flaky) and examples that passed every run (omitted -- nothing to report).
- Each round's seed is included in the response (`rounds[].seed`), so a
  specific divergence can be reproduced afterward with a plain
  `rails_spec_run(seed: <that seed>)`.
- `timeout_seconds` is a **per-round** budget, not a total; `runs *
  timeout_seconds` is capped at 1800s combined (`flaky_check_budget_exceeded`
  if exceeded) since this tool can run for a while.
- Selections over 500 examples are capped per round (the same limit
  `rails_spec_run` already has), and each round samples a different subset,
  since execution order varies by design -- for suites this large, narrow
  `paths`/`example` rather than passing a very broad directory selection.
- `statuses[]` only aligns positionally with `rounds[]` when no round
  crashed -- a round whose process itself failed contributes no entry to
  `statuses[]` (though it still appears in `rounds[]`), so treat positional
  correspondence as best-effort, not guaranteed, when a round's `status` in
  `rounds[]` looks like an outright crash rather than a normal pass/fail.

The warm test worker forces Rails' reload-checking on for its own boot,
regardless of the target app's own `test.rb` setting (which disables it by
default) -- so editing a model file takes effect on the next tool call
without needing to restart Coatepec. This is not limited to metadata reads:
because the setting is applied to the whole worker process, `rails_spec_run`
also executes your specs with `enable_reloading = true` and `cache_classes =
false` rather than whatever your own `config/environments/test.rb` asks for
(the file watcher is additionally pinned to the polling
`ActiveSupport::FileUpdateChecker`, so no `listen` threads are started in the
worker). For most apps this is invisible, but if you ever see behavior differ
between Coatepec and your own `bundle exec rspec`, this is the first thing to
suspect.

### Restarts

If any tool call fails with `sidecar_restart_required`, the target app's
`Gemfile`/`Gemfile.lock` changed since Coatepec's own parent process (the
"sidecar") started -- not just the warm test worker, which Coatepec restarts
on its own. This is expected any time you switch branches, pull, or rebase
across a commit that touches the Gemfile, since the sidecar is managed by
your MCP client rather than by Coatepec itself: restart your MCP client (or
however it manages the Coatepec process) to pick up the change.

A dead *worker* (as opposed to a dead sidecar) recovers on its own: the
next tool call detects it and transparently boots a fresh one before
retrying, whether the worker exited outright or a request to it failed
with a broken pipe. If you want a fresh worker without waiting for a
failure -- or one keeps recurring -- call `rails_runtime_restart` directly;
it always respawns, even if the current worker looks healthy.

## Security boundary

No eval, console, SQL/record access, shell, Rake, or file-write tool. Spec
selectors must resolve inside an allowed spec root (`spec/`, `packs/*/spec/`,
`engines/*/spec/`, `gems/*/spec/`); absolute paths, `..`, symlink escapes,
non-`_spec.rb` files, and more than 100 selectors are rejected. RSpec still
executes application-controlled code; only run Coatepec against a trusted
checkout.

### Compared to Rails Active MCP

[Rails Active MCP](https://github.com/GoodPie/rails-active-mcp) is a
different MCP server for Rails apps built around a `console_execute` tool:
arbitrary Ruby runs in your Rails console, gated by pattern-based
"dangerous operation" detection (blocking things like mass deletions,
`eval`, or raw SQL) rather than by not offering code execution at all --
sophisticated bypasses of a denylist like that are always possible in
principle.

Coatepec takes the opposite approach: there's no eval, console, or SQL tool
to begin with. `rails_spec_run` only ever executes RSpec files that already
exist under the app's own allowed spec roots, and `rails_routes`/
`rails_model`/`rails_job` only ever call structured, read-only Rails APIs
(`Rails.application.routes.routes`, `ActiveRecord` reflection, `ActiveJob`
class/callback introspection) -- never `eval`, `const_get` on unvalidated
input, or arbitrary method dispatch. `rails_job` never evaluates a job's
dynamic `queue_as`/`queue_with_priority` block either -- it reports
`"(dynamic)"`/`"(block)"` instead of executing app code to compute a real
value. If you genuinely need a Rails console over MCP, Rails Active MCP is
built for that; Coatepec is for teams who want an agent to run specs and
read structure without ever handing it a REPL.

## Compatibility

Ruby `>= 3.2`, Rails `>= 7.1, < 8.2`. CI tests three lanes: Rails 8.1 on
Linux (primary), Rails 7.1 on Linux (compat), and Rails 8.1 on macOS (which
is where the guarded-fork path above actually forks).

## Development

```bash
bundle install
bundle exec rake spec:unit          # fast, no Rails boot
bundle exec rake spec:integration   # boots the fixture Rails app
bundle exec rake                    # full suite + rubocop
```

## License

Coatepec is available under the MIT License. See `LICENSE.txt`.
