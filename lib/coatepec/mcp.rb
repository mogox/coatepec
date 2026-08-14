# frozen_string_literal: true

begin
  require "mcp"
rescue LoadError
  raise LoadError, "The \"mcp\" gem is required to run Coatepec but is not installed. " \
    "Install it alongside Coatepec: `gem install coatepec mcp`."
end

require "coatepec"
require_relative "mcp/response"
require_relative "mcp/tools"

module Coatepec
  # Wires the `rails_spec_run`, `rails_runtime_status`, `rails_runtime_restart`,
  # `rails_spec_flaky_check`, `rails_routes`, and `rails_model` tools into an
  # `::MCP::Server` instance backed by the given project's worker manager.
  module MCP
    def self.build_server(project:, worker_manager:)
      ::MCP::Server.new(
        name: "coatepec",
        version: Coatepec::VERSION,
        tools: [SpecRunTool, RuntimeStatusTool, RuntimeRestartTool, FlakyCheckTool, RoutesTool, ModelTool],
        server_context: { worker_manager: worker_manager, project_root: project.root }
      )
    end
  end
end
