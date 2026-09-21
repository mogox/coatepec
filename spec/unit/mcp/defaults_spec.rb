# frozen_string_literal: true

require "spec_helper"
require "coatepec/mcp/defaults"

RSpec.describe Coatepec::MCP::Defaults do
  let(:root) { "/app" }

  def with_config(**by_tool)
    config = instance_double(Coatepec::ProjectConfig)
    allow(config).to receive(:defaults_for) { |tool| by_tool.fetch(tool, {}) }
    allow(Coatepec::ProjectConfig).to receive(:new).with(root).and_return(config)
  end

  it "returns the built-ins when nothing is given or configured" do
    with_config

    expect(described_class.resolve(:spec_run, root))
      .to eq(include_passing: false, include_stdout: "failures", timeout_seconds: 120)
    expect(described_class.resolve(:routes, root)).to eq(engines: "exclude")
  end

  it "lets the project config override a built-in and a call argument override both" do
    with_config(spec_run: { include_stdout: "always", timeout_seconds: 300 })

    resolved = described_class.resolve(:spec_run, root, include_stdout: "never", timeout_seconds: nil,
                                                        include_passing: nil)

    expect(resolved).to eq(include_passing: false, include_stdout: "never", timeout_seconds: 300)
  end

  # nil means omitted; false is a value a caller chose.
  it "treats false as given, not omitted" do
    with_config(spec_run: { include_passing: true })

    expect(described_class.resolve(:spec_run, root, include_passing: false)[:include_passing]).to be(false)
  end

  it "re-reads the project config on every call" do
    with_config
    described_class.resolve(:routes, root)
    described_class.resolve(:routes, root)

    expect(Coatepec::ProjectConfig).to have_received(:new).with(root).twice
  end
end
