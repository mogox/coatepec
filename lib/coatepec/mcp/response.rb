# frozen_string_literal: true

require "json"
require "mcp"

module Coatepec
  module MCP
    module Response
      module_function

      def ok(data:, meta: {})
        payload = { ok: true, data: data, meta: meta }
        ::MCP::Tool::Response.new([{ type: "text", text: JSON.pretty_generate(payload) }])
      end

      def error(err)
        payload = {
          ok: false,
          error: { code: err.code.to_s, message: err.message, details: err.details }
        }
        ::MCP::Tool::Response.new([{ type: "text", text: JSON.pretty_generate(payload) }], error: true)
      end
    end
  end
end
