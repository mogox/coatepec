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
          include_passing: { type: "boolean" },
          include_stdout: { type: "string", enum: %w[failures always never] }
        },
        required: ["paths"],
        additionalProperties: false
      }.freeze

      # Kept a constant so the vocabulary clause stays readable next to the rest of the description.
      RSPEC_VOCABULARY =
        "; results use RSpec vocabulary for both frameworks: a Minitest error is status failed and is " \
        "counted in summary.failure_count (so it can exceed the failures number Minitest prints in " \
        "stdout) and a skip is pending"

      tool_name "rails_spec_run"
      description "Run targeted RSpec examples (spec/**/*_spec.rb) or Minitest tests (test/**/*_test.rb) " \
                  "against a warm, isolated Rails test worker; the framework is chosen from the selector " \
                  "paths; there is no separate Minitest tool#{RSPEC_VOCABULARY}" \
                  "; returns only failed and pending examples unless include_passing is true" \
                  "; failure blocks in stdout that repeat an earlier error are rolled up into one line" \
                  "; stdout is returned only for failing runs unless include_stdout is \"always\" or \"never\""
      annotations(read_only_hint: false, destructive_hint: true, idempotent_hint: false, open_world_hint: true)
      input_schema(**INPUT_SCHEMA)

      class << self
        def call(paths:, server_context:, example: nil, seed: nil, fail_fast: false, timeout_seconds: 120,
                 include_passing: false, include_stdout: "failures")
          started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          data = server_context[:worker_manager].run_spec(
            paths: paths, example: example, seed: seed, fail_fast: fail_fast, timeout_seconds: timeout_seconds,
            include_passing: include_passing, include_stdout: include_stdout
          )
          Response.ok(data: data, meta: Response.meta(started_at))
        rescue Coatepec::Error => e
          Response.error(e)
        end
      end
    end

    # The `rails_runtime_status` MCP tool: reports the test worker's Ruby/Rails
    # versions, PID, boot_id, lifecycle state and the project root. Worker::Server#handle boots
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
          data = server_context[:worker_manager].status.merge(project_root: server_context[:project_root])
          Response.ok(data: data, meta: Response.meta(started_at))
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
          Response.ok(data: data, meta: Response.meta(started_at))
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
          Response.ok(data: data, meta: Response.meta(started_at))
        rescue Coatepec::Error => e
          Response.error(e)
        end
      end
    end

    # The `rails_routes` MCP tool: lists/filters/paginates the target
    # Rails app's routes.
    class RoutesTool < ::MCP::Tool
      tool_name "rails_routes"
      description "Return a bounded, filterable list of the Rails app's routes, application routes only by " \
                  "default: mounted-engine routes (for example admin scaffolding) are withheld and the response's " \
                  "engines_excluded says how many routes matching the query the engines filter held back " \
                  "(application routes, under \"only\"); pass " \
                  "engines: \"include\" to list both or \"only\" for engine routes alone. Engine routes are " \
                  "expanded one level deep, carry the mount point in their path, and name their engine in the " \
                  "engine field (null for an application route; query also matches that field); returns up to " \
                  "limit items (default 100) with next_offset -- the offset to pass back for the next page, " \
                  "null on the last one"
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)
      input_schema(
        properties: {
          query: { type: %w[string null] },
          limit: { type: "integer", minimum: 1, maximum: 200 },
          offset: { type: "integer", minimum: 0 },
          engines: { type: "string", enum: %w[include exclude only] }
        },
        required: [],
        additionalProperties: false
      )

      class << self
        def call(server_context:, query: nil, limit: 100, offset: 0, engines: Introspection::Routes::DEFAULT_ENGINES)
          started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          data = server_context[:worker_manager].routes(query: query, limit: limit, offset: offset, engines: engines)
          Response.ok(data: data, meta: Response.meta(started_at))
        rescue Coatepec::Error => e
          Response.error(e)
        end
      end
    end

    # The `rails_model` MCP tool: returns an ActiveRecord model's schema,
    # associations, validators, and enums.
    class ModelTool < ::MCP::Tool
      tool_name "rails_model"
      description "Return bounded ActiveRecord schema, associations, validators, and enums for a model, " \
                  "without row data; counts (the size of each of those four lists) is always present, and fields " \
                  "(any of columns, associations, validators, enums) limits which lists are returned -- fields: [] " \
                  "is the cheapest way to answer a how-many question; validators are de-duplicated by class, " \
                  "attributes and options, so the list holds distinct validators and can be shorter than " \
                  "klass.validators; an array-valued validator option longer than 20 entries keeps its first 20 " \
                  "with <option>_count and <option>_truncated beside it"
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)
      input_schema(
        properties: {
          name: { type: "string", pattern: '^[A-Z]\w*(?:::[A-Z]\w*)*$' },
          fields: { type: "array", items: { type: "string", enum: %w[columns associations validators enums] },
                    uniqueItems: true }
        },
        required: ["name"],
        additionalProperties: false
      )

      class << self
        def call(name:, server_context:, fields: nil)
          started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          data = server_context[:worker_manager].model(name: name, fields: fields)
          Response.ok(data: data, meta: Response.meta(started_at))
        rescue Coatepec::Error => e
          Response.error(e)
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
          Response.ok(data: data, meta: Response.meta(started_at))
        rescue Coatepec::Error => e
          Response.error(e)
        end
      end
    end
  end
end
