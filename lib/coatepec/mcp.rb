# frozen_string_literal: true

require "mcp"
require "coatepec"
require_relative "mcp/response"
require_relative "mcp/tools"

module Coatepec
  module MCP
    def self.build_server(project:, worker_manager:)
      ::MCP::Server.new(
        name: "coatepec",
        version: Coatepec::VERSION,
        tools: [SpecRunTool, RuntimeStatusTool],
        server_context: { worker_manager: worker_manager, project_root: project.root }
      )
    end
  end
end
