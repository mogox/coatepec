# frozen_string_literal: true

require "json"
require "mcp"

module Coatepec
  module MCP
    # Builds the compact JSON `{ok: true, data:, meta:}` / `{ok: false, error:}`
    # envelope every tool response wraps in one text block.
    module Response
      # Per-stream caps in Spec::Result bound stdout/stderr, but a fully assembled
      # envelope can still exceed what an MCP client accepts, so cap it here.
      MAX_RESPONSE_BYTES = 1024 * 1024

      module_function

      def ok(data:, meta: {})
        text = generate(ok: true, data: data, meta: meta)
        return oversized_response if text.bytesize > MAX_RESPONSE_BYTES

        ::MCP::Tool::Response.new([{ type: "text", text: text }])
      end

      def error(err)
        payload = {
          ok: false,
          error: { code: err.code.to_s, message: err.message, details: err.details }
        }
        ::MCP::Tool::Response.new([{ type: "text", text: generate(payload) }], error: true)
      end

      def oversized_response
        error(Coatepec::Error.new(:response_too_large, "Result exceeds the 1 MiB response limit"))
      end

      # Compact by default: nothing downstream reads the indentation. COATEPEC_PRETTY=1 restores it for hand debugging.
      def generate(payload)
        ENV["COATEPEC_PRETTY"] == "1" ? JSON.pretty_generate(payload) : JSON.generate(payload)
      end
    end
  end
end
