# frozen_string_literal: true

require "json"
require "mcp"

module Coatepec
  module MCP
    # Builds the pretty-printed JSON `{ok: true, data:, meta:}` / `{ok: false,
    # error:}` envelope that every Coatepec tool response wraps in a single
    # text content block.
    module Response
      # Per-stream caps in Spec::Result bound stdout/stderr, but the fully
      # assembled envelope (500 examples with long descriptions) can still
      # exceed what an MCP client will accept, so cap it here -- the single
      # place every tool response is built.
      MAX_RESPONSE_BYTES = 1024 * 1024

      module_function

      def ok(data:, meta: {})
        text = JSON.pretty_generate(ok: true, data: data, meta: meta)
        return oversized_response if text.bytesize > MAX_RESPONSE_BYTES

        ::MCP::Tool::Response.new([{ type: "text", text: text }])
      end

      def error(err)
        payload = {
          ok: false,
          error: { code: err.code.to_s, message: err.message, details: err.details }
        }
        ::MCP::Tool::Response.new([{ type: "text", text: JSON.pretty_generate(payload) }], error: true)
      end

      def oversized_response
        error(Coatepec::Error.new(:response_too_large, "Result exceeds the 1 MiB response limit"))
      end
    end
  end
end
