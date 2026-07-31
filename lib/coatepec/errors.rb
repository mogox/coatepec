# frozen_string_literal: true

module Coatepec
  class Error < StandardError
    attr_reader :code, :details

    def initialize(code, message = nil, details: {})
      @code = code
      @details = details
      super(message || code.to_s)
    end
  end
end
