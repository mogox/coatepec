# frozen_string_literal: true

module Coatepec
  module MCP
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
        required: ["paths"]
      )

      class << self
        def call(paths:, server_context:, example: nil, seed: nil, fail_fast: false, timeout_seconds: 120)
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

    class RuntimeStatusTool < ::MCP::Tool
      tool_name "rails_runtime_status"
      description "Report the Coatepec test worker's identity and boot status"
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)
      input_schema(properties: {}, required: [])

      class << self
        def call(server_context:)
          started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          data = server_context[:worker_manager].status
          duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
          Response.ok(data: data, meta: { project_root: server_context[:project_root], environment: "test", duration_ms: duration_ms })
        rescue Coatepec::Error => e
          Response.error(e)
        end
      end
    end
  end
end
