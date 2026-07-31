# frozen_string_literal: true

require "spec_helper"
require "coatepec/mcp"

RSpec.describe "Coatepec MCP tools" do
  let(:worker_manager) { instance_double(Coatepec::WorkerManager) }
  let(:server_context) { { worker_manager: worker_manager, project_root: "/app" } }

  describe Coatepec::MCP::SpecRunTool do
    it "returns an ok envelope with the runner's data" do
      allow(worker_manager).to receive(:run_spec)
        .with(paths: ["spec/x_spec.rb"], example: nil, seed: nil, fail_fast: false, timeout_seconds: 120)
        .and_return(status: "passed")

      response = described_class.call(paths: ["spec/x_spec.rb"], server_context: server_context)
      payload = JSON.parse(response.content.first[:text])

      expect(response.error?).to be(false)
      expect(payload["data"]).to eq("status" => "passed")
      expect(payload["meta"]["project_root"]).to eq("/app")
    end

    it "returns an error envelope when the worker manager raises" do
      allow(worker_manager).to receive(:run_spec).and_raise(Coatepec::Error.new(:invalid_spec_path, "bad"))

      response = described_class.call(paths: ["../x"], server_context: server_context)
      payload = JSON.parse(response.content.first[:text])

      expect(response.error?).to be(true)
      expect(payload["error"]["code"]).to eq("invalid_spec_path")
    end
  end

  describe Coatepec::MCP::RuntimeStatusTool do
    it "returns an ok envelope with the worker status" do
      allow(worker_manager).to receive(:status).and_return(environment: "test")

      response = described_class.call(server_context: server_context)
      payload = JSON.parse(response.content.first[:text])

      expect(payload["data"]).to eq("environment" => "test")
    end
  end

  it "registers both tools on a built server" do
    project = instance_double(Coatepec::Project, root: "/app")
    server = Coatepec::MCP.build_server(project: project, worker_manager: worker_manager)

    expect(server.tools.keys).to contain_exactly("rails_spec_run", "rails_runtime_status")
  end

  describe "input schema strictness" do
    it "rejects unknown arguments to rails_spec_run" do
      expect { Coatepec::MCP::SpecRunTool.input_schema.validate_arguments("paths" => ["spec/x_spec.rb"], "oops" => 1) }
        .to raise_error(::MCP::Tool::InputSchema::ValidationError, /disallowed additional property/)
    end

    it "rejects unknown arguments to rails_runtime_status" do
      expect { Coatepec::MCP::RuntimeStatusTool.input_schema.validate_arguments("oops" => 1) }
        .to raise_error(::MCP::Tool::InputSchema::ValidationError, /disallowed additional property/)
    end

    it "still accepts the documented rails_spec_run arguments" do
      expect { Coatepec::MCP::SpecRunTool.input_schema.validate_arguments("paths" => ["spec/x_spec.rb"]) }
        .not_to raise_error
    end
  end
end
