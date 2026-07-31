# Coatepec

Coatepec gives coding agents a bounded way to run targeted RSpec examples
against a Rails application, over MCP, without exposing a general Rails
console.

## Quickstart

```ruby
# Gemfile
group :development, :test do
  gem "coatepec", require: false
end
```

```bash
bundle install
bundle exec coatepec --version
```

Configure your MCP client to run `bundle exec coatepec --root /absolute/path/to/app`
from the Rails application's own bundle.

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

## Tools

| Tool | Input | Notes |
|---|---|---|
| `rails_spec_run` | `paths: string[1..100]`, `example?`, `seed?`, `fail_fast?`, `timeout_seconds?` (1..900, default 120) | Isolated per run; output capped at 256 KiB per stream |
| `rails_runtime_status` | `{}` | Reports Ruby/Rails versions, worker PID, boot_id, lifecycle state |

## Security boundary

No eval, console, SQL/record access, shell, Rake, or file-write tool. Spec
selectors must resolve inside an allowed spec root (`spec/`, `packs/*/spec/`,
`engines/*/spec/`, `gems/*/spec/`); absolute paths, `..`, symlink escapes,
non-`_spec.rb` files, and more than 100 selectors are rejected. RSpec still
executes application-controlled code; only run Coatepec against a trusted
checkout.

## Compatibility

Ruby `>= 3.2`, Rails `>= 7.1, < 8.2`. CI tests three lanes: Rails 8.1 on
Linux (primary), Rails 7.1 on Linux (compat), and Rails 8.1 on macOS (which
is where the guarded-fork path below actually forks).

## Development

```bash
bundle install
bundle exec rake spec:unit          # fast, no Rails boot
bundle exec rake spec:integration   # boots the fixture Rails app
bundle exec rake                    # full suite + rubocop
```

## License

Coatepec is available under the MIT License. See `LICENSE.txt`.
