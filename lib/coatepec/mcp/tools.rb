# frozen_string_literal: true

module Coatepec
  module MCP
    # The `rails_spec_run` MCP tool: runs targeted RSpec examples against
    # the warm test worker and returns a structured pass/fail result.
    class SpecRunTool < ::MCP::Tool
      tool_name "rails_spec_run"
      description "Run targeted RSpec examples against a warm, isolated Rails test worker"
      annotations(read_only_hint: false, destructive_hint: true, idempotent_hint: false, open_world_hint: true)
      input_schema(
        properties: {
          paths: { type: "array", items: { type: "string" }, minItems: 1, maxItems: 100 },
          example: { type: %w[string null] },
          seed: { type: %w[integer null], minimum: 0, maximum: 65_535 },
          fail_fast: { type: "boolean" },
          timeout_seconds: { type: "integer", minimum: 1, maximum: 900 }
        },
        required: ["paths"],
        additionalProperties: false
      )

      class << self
        # rubocop:disable Metrics/ParameterLists -- mirrors the tool's own input_schema
        # (paths/example/seed/fail_fast/timeout_seconds) plus the MCP-framework-injected
        # server_context; splitting it would fight the ::MCP::Tool#call contract.
        def call(paths:, server_context:, example: nil, seed: nil, fail_fast: false, timeout_seconds: 120)
          # rubocop:enable Metrics/ParameterLists
          started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          data = server_context[:worker_manager].run_spec(
            paths: paths, example: example, seed: seed, fail_fast: fail_fast, timeout_seconds: timeout_seconds
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

    # The `rails_routes` MCP tool: lists/filters/paginates the target
    # Rails app's routes.
    class RoutesTool < ::MCP::Tool
      tool_name "rails_routes"
      description "Return a bounded, filterable list of the Rails app's routes"
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
        def call(server_context:, query: nil, limit: 50, offset: 0)
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
  end
end
