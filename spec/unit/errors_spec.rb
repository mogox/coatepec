require "spec_helper"

RSpec.describe Coatepec::Error do
  it "carries a code, message, and details" do
    error = described_class.new(:invalid_spec_path, "bad path", details: { path: "x" })

    expect(error.code).to eq(:invalid_spec_path)
    expect(error.message).to eq("bad path")
    expect(error.details).to eq(path: "x")
  end

  it "defaults the message to the code" do
    error = described_class.new(:worker_failure)

    expect(error.message).to eq("worker_failure")
    expect(error.details).to eq({})
  end
end
