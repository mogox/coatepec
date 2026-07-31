# frozen_string_literal: true

require "spec_helper"

RSpec.describe Coatepec::Worker::Client, type: :integration do
  after { @client&.stop }

  it "spawns a worker, answers status, and reports alive?" do
    @client = described_class.spawn(FIXTURE_APP_ROOT)

    expect(@client.alive?).to be(true)
    data = @client.request("status", {})
    expect(data[:environment]).to eq("test")
  end

  it "raises DisconnectedError after stop" do
    @client = described_class.spawn(FIXTURE_APP_ROOT)
    @client.stop

    expect(@client.alive?).to be(false)
    expect { @client.request("status", {}) }.to raise_error(Coatepec::Worker::Client::DisconnectedError)
  end

  it "raises the worker's structured error for a bad command" do
    @client = described_class.spawn(FIXTURE_APP_ROOT)

    expect { @client.request("spec_run", { paths: ["../Gemfile"] }) }
      .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:invalid_spec_path) }
  end
end
