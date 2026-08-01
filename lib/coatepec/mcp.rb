# frozen_string_literal: true

require "mcp"
require "coatepec"
require_relative "mcp/response"
require_relative "mcp/tools"

module Coatepec
  # Wires the `rails_spec_run`, `rails_runtime_status`, `rails_routes`, and
  # `rails_model` tools into an `::MCP::Server` instance backed by the given
  # project's worker manager.
  module MCP
    def self.build_server(project:, worker_manager:)
      ::MCP::Server.new(
        name: "coatepec",
        version: Coatepec::VERSION,
        tools: [SpecRunTool, RuntimeStatusTool, RoutesTool, ModelTool],
        server_context: { worker_manager: worker_manager, project_root: project.root }
      )
    end
  end
end
