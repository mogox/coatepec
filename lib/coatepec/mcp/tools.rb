# frozen_string_literal: true

module Coatepec
  module MCP
    # The `rails_spec_run` MCP tool: runs targeted RSpec examples or Minitest
    # tests (chosen from the selector paths) against the warm test worker and
    # returns a structured pass/fail result.
    class SpecRunTool < ::MCP::Tool
      INPUT_SCHEMA = {
        properties: {
          paths: { type: "array", items: { type: "string" }, minItems: 1, maxItems: 100 },
          example: { type: %w[string null] },
          seed: { type: %w[integer null], minimum: 0, maximum: 65_535 },
          fail_fast: { type: "boolean" },
          timeout_seconds: { type: "integer", minimum: 1, maximum: 900 },
          include_passing: { type: "boolean" }
        },
        required: ["paths"],
        additionalProperties: false
      }.freeze

      tool_name "rails_spec_run"
      description "Run targeted RSpec examples (spec/**/*_spec.rb) or Minitest tests (test/**/*_test.rb) " \
                  "against a warm, isolated Rails test worker; the framework is chosen from the selector paths" \
                  "; returns only failed and pending examples unless include_passing is true"
      annotations(read_only_hint: false, destructive_hint: true, idempotent_hint: false, open_world_hint: true)
      input_schema(**INPUT_SCHEMA)

      class << self
        # rubocop:disable Metrics/ParameterLists -- mirrors the tool's own input_schema
        # (paths/example/seed/fail_fast/timeout_seconds/include_passing) plus the MCP-framework-injected
        # server_context; splitting it would fight the ::MCP::Tool#call contract.
        def call(paths:, server_context:, example: nil, seed: nil, fail_fast: false, timeout_seconds: 120,
                 include_passing: false)
          # rubocop:enable Metrics/ParameterLists
          started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          data = server_context[:worker_manager].run_spec(
            paths: paths, example: example, seed: seed, fail_fast: fail_fast, timeout_seconds: timeout_seconds,
            include_passing: include_passing
          )
          Response.ok(data: data, meta: meta_for(server_context, started_at))
        rescue Coatepec::Error => e
          Response.error(e)
        end

        private

        def meta_for(server_context, started_at)
          duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
          { project_root: server_context[:project_root], environment: "test", duration_ms: duration_ms }
        end
      end
    end

    # Alias of rails_spec_run for agents that reason from "this app uses
    # Minitest". Same schema object, same inherited #call; only the name
    # and description differ. The mcp gem's Tool.inherited resets every
    # declared attribute on a subclass, so each must be redeclared here.
    class TestRunTool < SpecRunTool
      tool_name "rails_test_run"
      description "Alias of rails_spec_run: run targeted Minitest tests (test/**/*_test.rb) or RSpec examples " \
                  "(spec/**/*_spec.rb) against the warm Rails test worker -- identical behaviour under either name" \
                  "; returns only failed and pending examples unless include_passing is true"
      annotations(read_only_hint: false, destructive_hint: true, idempotent_hint: false, open_world_hint: true)
      input_schema(**INPUT_SCHEMA)
    end

    # The `rails_runtime_status` MCP tool: reports the test worker's Ruby/Rails
    # versions, PID, boot_id, and lifecycle state. Worker::Server#handle boots
    # the Rails runtime before dispatching any command, so the first call to
    # this tool starts (and blocks on) a full Rails boot just like a spec run.
    class RuntimeStatusTool < ::MCP::Tool
      tool_name "rails_runtime_status"
      description "Report the Coatepec test worker's identity and boot status " \
                  "(boots the warm worker if it is not up yet)"
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)
      input_schema(properties: {}, required: [], additionalProperties: false)

      class << self
        def call(server_context:)
          started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          data = server_context[:worker_manager].status
          duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
          Response.ok(data: data,
                      meta: { project_root: server_context[:project_root], environment: "test",
                              duration_ms: duration_ms })
        rescue Coatepec::Error => e
          Response.error(e)
        end
      end
    end

    # The `rails_runtime_restart` MCP tool: unconditionally tears down and
    # respawns the test worker, discarding its warm Rails boot. A manual
    # escape hatch alongside WorkerManager's own automatic dead-worker
    # detection, for whatever failure mode that detection doesn't catch.
    class RuntimeRestartTool < ::MCP::Tool
      tool_name "rails_runtime_restart"
      description "Tear down and respawn the Coatepec test worker, discarding its warm Rails boot " \
                  "(use if rails_spec_run/rails_runtime_status keep failing and a fresh worker is needed)"
      annotations(read_only_hint: false, destructive_hint: true, idempotent_hint: false, open_world_hint: false)
      input_schema(properties: {}, required: [], additionalProperties: false)

      class << self
        def call(server_context:)
          started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          data = server_context[:worker_manager].restart!
          duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
          Response.ok(data: data,
                      meta: { project_root: server_context[:project_root], environment: "test",
                              duration_ms: duration_ms })
        rescue Coatepec::Error => e
          Response.error(e)
        end
      end
    end

    # The `rails_spec_flaky_check` MCP tool: runs targeted RSpec examples or
    # Minitest tests multiple times with independently random seeds and
    # reports which tests' pass/fail status was inconsistent across rounds.
    # Separate tool from rails_spec_run for the same reason rails_spec_profile
    # is -- see docs/superpowers/specs/2026-08-13-flaky-spec-detection-design.md.
    class FlakyCheckTool < ::MCP::Tool
      INPUT_SCHEMA = {
        properties: {
          paths: { type: "array", items: { type: "string" }, minItems: 1, maxItems: 100 },
          example: { type: %w[string null] },
          timeout_seconds: { type: "integer", minimum: 1, maximum: 900 },
          runs: { type: "integer", minimum: 2, maximum: 20 }
        },
        required: ["paths"],
        additionalProperties: false
      }.freeze

      tool_name "rails_spec_flaky_check"
      description "Run targeted RSpec examples or Minitest tests multiple times with random seeds to detect " \
                  "order-dependent or intermittent flakiness, reporting which tests' status was inconsistent " \
                  "across runs; the framework is chosen from the selector paths"
      annotations(read_only_hint: false, destructive_hint: true, idempotent_hint: false, open_world_hint: true)
      input_schema(**INPUT_SCHEMA)

      class << self
        def call(paths:, server_context:, example: nil, timeout_seconds: 120, runs: 5)
          started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          data = server_context[:worker_manager].check_flaky(
            paths: paths, example: example, timeout_seconds: timeout_seconds, runs: runs
          )
          Response.ok(data: data, meta: meta_for(server_context, started_at))
        rescue Coatepec::Error => e
          Response.error(e)
        end

        private

        def meta_for(server_context, started_at)
          duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
          { project_root: server_context[:project_root], environment: "test", duration_ms: duration_ms }
        end
      end
    end

    # Alias of rails_spec_flaky_check; see TestRunTool for why the
    # attributes are redeclared.
    class TestFlakyCheckTool < FlakyCheckTool
      tool_name "rails_test_flaky_check"
      description "Alias of rails_spec_flaky_check: rerun targeted Minitest tests or RSpec examples with random " \
                  "seeds to detect flakiness -- identical behaviour under either name"
      annotations(read_only_hint: false, destructive_hint: true, idempotent_hint: false, open_world_hint: true)
      input_schema(**INPUT_SCHEMA)
    end

    # The `rails_routes` MCP tool: lists/filters/paginates the target
    # Rails app's routes.
    class RoutesTool < ::MCP::Tool
      tool_name "rails_routes"
      description "Return a bounded, filterable list of the Rails app's routes, including the routes of mounted " \
                  "engines (one level deep; paths carry the mount point; each item's engine field names the " \
                  "engine, null for an application route; query also matches the engine field)" \
                  "; returns up to limit items (default 100) with next_offset -- the offset to pass back " \
                  "for the next page, null on the last one"
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)
      input_schema(
        properties: {
          query: { type: %w[string null] },
          limit: { type: "integer", minimum: 1, maximum: 200 },
          offset: { type: "integer", minimum: 0 }
        },
        required: [],
        additionalProperties: false
      )

      class << self
        def call(server_context:, query: nil, limit: 100, offset: 0)
          started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          data = server_context[:worker_manager].routes(query: query, limit: limit, offset: offset)
          Response.ok(data: data, meta: meta_for(server_context, started_at))
        rescue Coatepec::Error => e
          Response.error(e)
        end

        private

        def meta_for(server_context, started_at)
          duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
          { project_root: server_context[:project_root], environment: "test", duration_ms: duration_ms }
        end
      end
    end

    # The `rails_model` MCP tool: returns an ActiveRecord model's schema,
    # associations, validators, and enums.
    class ModelTool < ::MCP::Tool
      tool_name "rails_model"
      description "Return bounded ActiveRecord schema, associations, validators, and enums for a model, " \
                  "without row data"
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)
      input_schema(
        properties: {
          name: { type: "string", pattern: '^[A-Z]\w*(?:::[A-Z]\w*)*$' }
        },
        required: ["name"],
        additionalProperties: false
      )

      class << self
        def call(name:, server_context:)
          started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          data = server_context[:worker_manager].model(name: name)
          Response.ok(data: data, meta: meta_for(server_context, started_at))
        rescue Coatepec::Error => e
          Response.error(e)
        end

        private

        def meta_for(server_context, started_at)
          duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
          { project_root: server_context[:project_root], environment: "test", duration_ms: duration_ms }
        end
      end
    end

    # The `rails_controller` MCP tool: returns a controller's actions, action
    # callbacks, included concerns, and the routes reaching each action.
    class ControllerTool < ::MCP::Tool
      tool_name "rails_controller"
      description "Return a Rails controller's actions, action callbacks, concerns, and the routes " \
                  "reaching each action, including unroutable actions and routes with no matching action"
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)
      input_schema(
        properties: {
          name: { type: "string", pattern: '^[A-Z]\w*(?:::[A-Z]\w*)*$' }
        },
        required: ["name"],
        additionalProperties: false
      )

      class << self
        def call(name:, server_context:)
          started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          data = server_context[:worker_manager].controller(name: name)
          Response.ok(data: data, meta: meta_for(server_context, started_at))
        rescue Coatepec::Error => e
          Response.error(e)
        end

        private

        def meta_for(server_context, started_at)
          duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
          { project_root: server_context[:project_root], environment: "test", duration_ms: duration_ms }
        end
      end
    end
  end
end
