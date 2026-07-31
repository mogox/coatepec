# frozen_string_literal: true

require "spec_helper"
require "coatepec/mcp/response"

RSpec.describe Coatepec::MCP::Response do
  describe ".ok" do
    it "wraps data and meta in a pretty-printed ok envelope" do
      response = described_class.ok(data: { foo: "bar" }, meta: { environment: "test" })
      payload = JSON.parse(response.content.first[:text])

      expect(response.error?).to be(false)
      expect(payload).to eq(
        "ok" => true,
        "data" => { "foo" => "bar" },
        "meta" => { "environment" => "test" }
      )
    end

    it "returns a response_too_large error when the envelope exceeds 1 MiB" do
      response = described_class.ok(data: { blob: "x" * (2 * 1024 * 1024) })
      payload = JSON.parse(response.content.first[:text])

      expect(response.error?).to be(true)
      expect(payload["ok"]).to be(false)
      expect(payload["error"]["code"]).to eq("response_too_large")
    end

    it "does not flag an envelope that fits within the limit" do
      response = described_class.ok(data: { blob: "x" * 1024 })

      expect(response.error?).to be(false)
    end
  end

  describe ".error" do
    it "wraps a Coatepec::Error in an error envelope and marks isError" do
      err = Coatepec::Error.new(:invalid_spec_path, "bad path", details: { path: "x" })
      response = described_class.error(err)
      payload = JSON.parse(response.content.first[:text])

      expect(response.error?).to be(true)
      expect(payload).to eq(
        "ok" => false,
        "error" => { "code" => "invalid_spec_path", "message" => "bad path", "details" => { "path" => "x" } }
      )
    end
  end
end
