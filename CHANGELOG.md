# Changelog

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
