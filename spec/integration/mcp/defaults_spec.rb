# frozen_string_literal: true

require "spec_helper"
require "coatepec/mcp"
require "fileutils"

RSpec.describe "rails_spec_run defaults from .coatepec.yml", type: :integration do
  let(:config_path) { File.join(FIXTURE_APP_ROOT, ".coatepec.yml") }
  let(:manager) { Coatepec::WorkerManager.new(Coatepec::Project.new(FIXTURE_APP_ROOT)) }
  let(:server_context) { { worker_manager: manager, project_root: FIXTURE_APP_ROOT } }

  before { File.write(config_path, "defaults:\n  spec_run:\n    include_stdout: always\n") }
  after do
    FileUtils.rm_f(config_path)
    manager.stop
  end

  def run_tool(**args)
    response = Coatepec::MCP::SpecRunTool.call(paths: ["spec/passing_spec.rb"], server_context: server_context, **args)
    JSON.parse(response.content.first[:text])
  end

  it "applies the configured default when the input is omitted and lets the argument win" do
    configured = run_tool
    explicit = run_tool(include_stdout: "never")

    expect(configured["ok"]).to be(true), configured.inspect
    expect(configured["data"]["stdout"]).to include("1 example, 0 failures")
    expect(explicit["data"]["stdout"]).to be_nil
  end
end
