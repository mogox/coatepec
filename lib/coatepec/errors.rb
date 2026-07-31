# frozen_string_literal: true

module Coatepec
  # Structured error carrying a stable machine-readable `code` (and optional
  # `details`) that MCP tool handlers translate into JSON error responses.
  class Error < StandardError
    attr_reader :code, :details

    def initialize(code, message = nil, details: {})
      @code = code
      @details = details
      super(message || code.to_s)
    end
  end
end
