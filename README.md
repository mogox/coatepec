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
                              |-- Linux:  Process.fork  --> isolated RSpec/Minitest child
                              `-- macOS:  Process.spawn --> fresh RSpec/Minitest process (default)
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

Tool responses are compact JSON -- no indentation, nothing downstream reads
it. Set `COATEPEC_PRETTY=1` in the MCP server's `env` (the same place as
`OBJC_DISABLE_INITIALIZE_FORK_SAFETY` in the JSON example below) to
pretty-print them when you are reading the sidecar by hand.

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
| `rails_spec_run` | `paths: string[1..100]`, `example?`, `seed?`, `fail_fast?`, `timeout_seconds?` (1..900, default 120), `include_passing?`, `include_stdout?` | RSpec (`spec/**/*_spec.rb`) or Minitest (`test/**/*_test.rb`), chosen from the paths; isolated per run; output capped at 256 KiB per stream; failure blocks in `stdout` that repeat an earlier block's error verbatim are replaced by a roll-up line naming the tests; returns `summary` counts plus only the failed/pending `examples`, pass `include_passing: true` for the full roster (still capped at 500 examples); `include_stdout: false` nulls `stdout` (the per-test verdicts in `examples` and the counts in `summary` are unaffected); `child_pid`/`signaled`/`termsig`/`stopsig`/`coredump` appear only when the child did not exit normally (a timeout kill or a crash) |
| `rails_test_run` | same as `rails_spec_run` | Alias of `rails_spec_run` -- identical behaviour under either name |
| `rails_runtime_status` | `{}` | Reports Ruby/Rails versions, worker PID, boot_id, lifecycle state, and the project root (`project_root`) |
| `rails_runtime_restart` | `{}` | Unconditionally respawns the worker, discarding its warm boot |
| `rails_routes` | `query?`, `limit?` (1..200, default 100), `offset?`, `engines?` (`exclude` default, `include`, `only`) | Case-insensitive filter across name/verb/path/controller/action/engine. Application routes only by default; `engines: "include"` adds the routes of mounted engines (one level deep, paths prefixed with the mount point, `engine` naming the engine class; `null` for an application route), `"only"` returns just those. Every response carries `engines` (the filter applied) and `engines_excluded` (how many routes matching `query` the filter withheld), so nothing is hidden silently. The filter applies after `query` and before paging, so `matched`/`next_offset` describe the kept set. The engine's mount route counts as an application route. Routes Rails marks `internal` are omitted, like `bin/rails routes`. `next_offset` is the offset of the next page, or `null` on the last one |
| `rails_model` | `name` (constant path, e.g. `Widget` or `Admin::Widget`) | ActiveRecord models only; columns, associations, validators, enums -- no row data; validators are de-duplicated by class, attributes and options (a concern and the model body declaring the same validation count once), so the count can be lower than `klass.validators.size`; an array-valued validator option longer than 20 entries (a country-code `inclusion` list, say) is cut to its first 20 with `<option>_count` and `<option>_truncated: true` beside it |
| `rails_controller` | `name` (constant path, e.g. `WidgetsController` or `Admin::ReportsController`) | Actions, action callbacks, concerns, and the routes reaching each action -- no request dispatch |
| `rails_spec_flaky_check` | `paths`, `example?`, `timeout_seconds?` (per round, 1..900), `runs?` (2..20, default 5) | Runs the selection `runs` times with a fresh random seed each round; reports tests whose status was inconsistent across runs; RSpec or Minitest, chosen from the paths |
| `rails_test_flaky_check` | same as `rails_spec_flaky_check` | Alias of `rails_spec_flaky_check` |

### Example queries

`rails_routes`:

- "What are all the routes in this app?" -- `rails_routes()`, the
  application's own; add `engines: "include"` for the mounted engines' too.
- "What's the URL for widgets?" -- `rails_routes(query: "widget")`. `query` is a
  case-insensitive substring match across name, verb, path, controller, *and*
  action -- not just the path -- so a resource name alone typically returns
  every route for that resource (index/create/new/...); narrow further with
  something like `query: "new_widget"` to hit one route by name. The call
  already leaves out the admin engine's scaffolding, which is often two thirds
  of every match; the response's `engines_excluded` says how many engine routes
  it held back. Pass `engines: "include"` to see them too, or
  `engines: "only"` for just the engine's.
- "Which routes accept POST?" -- `rails_routes(query: "POST")`, the same
  substring match applied to the verb column.
- "Which routes does the Avo engine add?" --
  `rails_routes(query: "Avo::Engine", engines: "only")` -- the substring match
  covers the `engine` column too, so an engine's class name returns exactly the
  routes mounted from it. Application routes always sort before engine routes,
  so an unfiltered listing (with `engines: "include"`) reads the way
  `bin/rails routes` does.
- An engine route's `name` is relative to its engine, not a top-level url
  helper: `{"name": "audits", "path": "/widget_admin/audits(.:format)",
  "engine": "WidgetAdmin::Engine"}` is reached as
  `widget_admin.audits_path` -- `<mount name>.<name>_path`, where the mount
  name is the `name` of the mount route itself -- and `audits_path` alone
  does not exist on the application.
- An engine mounted at two paths is listed under both mount points, once per
  prefixed path, whenever engine routes are in scope, since each of those
  paths is a real, reachable URL.
  `bin/rails routes` keys engines by endpoint and so lists such an engine
  only once.
- Paging: when `next_offset` is not `null`, call again with
  `offset: next_offset` to get the next page.

`rails_model`:

- "What columns does Widget have, and which are nullable?" --
  `rails_model(name: "Widget")` -- see `columns[].null`, `columns[].sql_type`,
  `columns[].default`.
- "What validations and associations does Widget enforce?" -- same call --
  see `validators` and `associations`.
- A long allow-list is summarised, not enumerated: `validates :country_code,
  inclusion: { in: ISO_CODES }` with 249 codes comes back as `"in"` holding
  the first 20, `"in_count": 249` and `"in_truncated": true`. A list of 20 or
  fewer has no `_count`/`_truncated` siblings.
- "What happens if I ask about a non-model class, like a controller?" --
  `rails_model(name: "ApplicationController")` raises `not_active_record_model`
  rather than introspecting it (a nonexistent constant raises `model_not_found`
  instead) -- the tool only ever reflects on `ActiveRecord::Base` descendants.

`rails_controller`:

- "What actions does WidgetsController define, and what routes reach them?" --
  `rails_controller(name: "WidgetsController")` -- see `actions[].routes`,
  each with `verb`, `path` (Rails' raw route spec, `(.:format)` suffix
  included -- byte-identical to the same route's `path` from `rails_routes`),
  `route_name`, and `engine` (`null` for an application route, the engine's
  class name for a route that reaches this controller through a mount).
- "Does this controller have dead code, or a route that will 500?" -- same
  call -- see `unroutable_actions` (action methods no route reaches --
  probably dead code) and `routes_without_action` (action names the route
  table expects but the controller doesn't define -- a request to that route
  raises `AbstractController::ActionNotFound` in production; this is the
  tool's most actionable output).
- "What before/after/around filters run on this controller's actions, and
  under what conditions?" -- same call -- see `callbacks[]`: `kind`
  (`"before"`/`"after"`/`"around"`), `filter` (the method name, or `"(block)"`
  for a Proc), `only`/`except` (arrays of action names the filter is
  restricted to/excluded from, or `nil` if unrestricted -- `nil` and `[]` mean
  different things, so both are preserved: `nil` means no `only:`/`except:`
  was given at all, while `[]` means one *was* given but names no action this
  controller actually defines -- e.g. a typo or an action that was since
  removed -- so `only: []` never runs and `except: []` never skips), and
  `if`/`unless` (any remaining conditional, by symbol name or `"(block)"`).
- "What concerns does this controller pull in?" -- same call -- see
  `concerns`: app-defined modules only, whether included directly or
  inherited from a base class; framework modules (`ActionController::Base`
  and everything above it in the ancestor chain) are excluded.
- Unlike `concerns`, `callbacks[]` is *not* filtered to app code: it is the
  controller's full callback chain, so callbacks Rails itself installs show
  up too -- `verify_authenticity_token` / `verify_same_origin_request` from
  the default forgery protection, and a `"(block)"` entry for macros like
  `allow_browser` that register a Proc. Read the list as "everything that
  runs around an action", not "everything this app wrote".
- `rails_controller` admits `ActionController::API` controllers as well as
  `ActionController::Base` ones. A malformed constant name raises
  `invalid_controller_name`; a name that doesn't resolve raises
  `controller_not_found`; a name that resolves but isn't an
  `ActionController` descendant (a plain class, a model) raises
  `not_action_controller`.

`rails_controller` has one deliberate limitation:

- **Strong parameters are not reported.** `params.require(:widget).permit(:name,
  :size)` exists only as code inside a private method body, never as
  queryable class metadata -- the only way to recover a permit-list is to
  parse source, which this gem does not do (see `ROADMAP.md`'s "Considered
  and set aside" section for why source parsing is out of scope generally).

Routes drawn by an engine mounted in the application are cross-referenced
like any other, with the mount point on the path and the engine's class name
in `engine` -- so a controller that lives inside an engine reports its real
routes rather than listing every action as unroutable. Their `route_name` is
engine-local, reached as `<mount name>.<route_name>_path`, exactly as in
`rails_routes`. Expansion goes one level deep: an engine mounted inside
another engine stays an opaque mount route, the same boundary `bin/rails
routes` (and therefore `rails_routes`) draws.

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
- `description` is only present when it differs from `id` (RSpec); Minitest
  entries carry `id` only.
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

`rails_test_run` (Minitest):

- "Run this Minitest file" -- `rails_test_run(paths: ["test/models/widget_test.rb"])`,
  or the same call through `rails_spec_run`; the framework is decided by the
  path, not the tool name. `test/models/widget_test.rb:12` runs the one test
  whose definition spans line 12, and a directory runs every `_test.rb`
  under it.
- `example:` is a substring match on the test's method name
  (`example: "reaches the"` matches `test_reaches_the_database`), passed to
  Minitest as an escaped regex.
- Results use RSpec's vocabulary so the shape is identical: a Minitest skip
  is `"pending"`, an error is `"failed"` and counts toward
  `summary.failure_count` -- which is why that number can exceed the
  `failures` Minitest prints in `stdout`; `id` is `ClassName#test_method`.
- One call may not mix `spec/` and `test/` paths (`mixed_test_frameworks`).
- Rails' parallel testing is disabled in the child (`PARALLEL_WORKERS=1`), so
  a large directory selection runs serially under the one timeout budget
  rather than forking a worker tree.
- `file:LINE` works even when the app was generated with `--skip-test` (no
  `rails/test_unit/railtie`) or runs Rails 7.1 with Minitest 6, both of which
  break Rails' own line filtering; Coatepec installs its own.

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
selectors must resolve inside an allowed spec or test root (`spec/`, `test/`,
and the `packs/*/`, `engines/*/`, `gems/*/` variants of each); absolute
paths, `..`, symlink escapes, files that are neither `_spec.rb` under a spec
root nor `_test.rb` under a test root, and more than 100 selectors are
rejected. RSpec and Minitest still execute application-controlled code; only
run Coatepec against a trusted checkout.

### Compared to Rails Active MCP

[Rails Active MCP](https://github.com/GoodPie/rails-active-mcp) is a
different MCP server for Rails apps built around a `console_execute` tool:
arbitrary Ruby runs in your Rails console, gated by pattern-based
"dangerous operation" detection (blocking things like mass deletions,
`eval`, or raw SQL) rather than by not offering code execution at all --
sophisticated bypasses of a denylist like that are always possible in
principle.

Coatepec takes the opposite approach: there's no eval, console, or SQL
tool to begin with. `rails_spec_run` only ever executes RSpec or Minitest
files that already exist under the app's own allowed spec/test roots, and `rails_routes`/
`rails_model`/`rails_controller` only ever call structured, read-only Rails
APIs (`Rails.application.routes.routes`, `ActiveRecord` reflection,
`ActionController` callback/action-method metadata) -- never `eval`,
`const_get` on unvalidated input, or arbitrary method dispatch. If
you genuinely need a Rails console over MCP, Rails Active MCP is built for
that; Coatepec is for teams who want an agent to run specs and read
structure without ever handing it a REPL.

## Compatibility

Ruby `>= 3.2`, Rails `>= 7.1, < 8.2`, Minitest 5.x and 6.x (the fixture
apps pin 6.0.6; the 5.x name-filter flag is unit-tested). CI tests three
lanes: Rails 8.1 on Linux (primary), Rails 7.1 on Linux (compat), and Rails
8.1 on macOS (which is where the guarded-fork path above actually forks).

## Development

```bash
bundle install
bundle exec rake spec:unit          # fast, no Rails boot
bundle exec rake spec:integration   # boots the fixture Rails app
bundle exec rake                    # full suite + rubocop
```

## License

Coatepec is available under the MIT License. See `LICENSE.txt`.
