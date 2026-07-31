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
                              `-- macOS:  Process.spawn --> fresh RSpec process
```

See [Design](docs/superpowers/specs/2026-07-30-spec-runner-v1-design.md) for
the full rationale.

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

Ruby `>= 3.2`, Rails `>= 7.1, < 8.2`. CI tests Rails 8.1 (primary) and Rails
7.1 (compat lane).

## Development

```bash
bundle install
bundle exec rake spec:unit          # fast, no Rails boot
bundle exec rake spec:integration   # boots the fixture Rails app
bundle exec rake                    # full suite + rubocop
```

## License

Coatepec is available under the MIT License. See `LICENSE.txt`.
