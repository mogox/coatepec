# frozen_string_literal: true

require "json"

module Coatepec
  class Protocol
    class FramingError < StandardError; end

    def initialize(input:, output:)
      @input = input
      @output = output
    end

    def write(message)
      @output.puts(JSON.generate(message))
      @output.flush
    end

    def read
      line = @input.gets
      return nil if line.nil?

      JSON.parse(line, symbolize_names: true)
    rescue JSON::ParserError => e
      raise FramingError, "Malformed NDJSON message: #{e.message}"
    end
  end
end
