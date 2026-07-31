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
