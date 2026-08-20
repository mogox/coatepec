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

  describe Coatepec::MCP::RuntimeRestartTool do
    it "returns an ok envelope with the restarted worker's status" do
      allow(worker_manager).to receive(:restart!).and_return(environment: "test", pid: 999, boot_id: "abc")

      response = described_class.call(server_context: server_context)
      payload = JSON.parse(response.content.first[:text])

      expect(response.error?).to be(false)
      expect(payload["data"]).to eq("environment" => "test", "pid" => 999, "boot_id" => "abc")
    end

    it "returns an error envelope when the worker manager raises" do
      allow(worker_manager).to receive(:restart!).and_raise(Coatepec::Error.new(:worker_disconnected, "gone"))

      response = described_class.call(server_context: server_context)
      payload = JSON.parse(response.content.first[:text])

      expect(response.error?).to be(true)
      expect(payload["error"]["code"]).to eq("worker_disconnected")
    end
  end

  describe Coatepec::MCP::RoutesTool do
    it "returns an ok envelope with the routes data" do
      allow(worker_manager).to receive(:routes)
        .with(query: "widgets", limit: 50, offset: 0)
        .and_return(items: [], matched: 0, limit: 50, offset: 0)

      response = described_class.call(query: "widgets", limit: 50, offset: 0, server_context: server_context)
      payload = JSON.parse(response.content.first[:text])

      expect(response.error?).to be(false)
      expect(payload["data"]).to eq("items" => [], "matched" => 0, "limit" => 50, "offset" => 0)
    end

    it "returns an error envelope when the worker manager raises" do
      allow(worker_manager).to receive(:routes).and_raise(Coatepec::Error.new(:worker_disconnected, "gone"))

      response = described_class.call(query: nil, limit: 50, offset: 0, server_context: server_context)
      payload = JSON.parse(response.content.first[:text])

      expect(response.error?).to be(true)
      expect(payload["error"]["code"]).to eq("worker_disconnected")
    end
  end

  describe Coatepec::MCP::ModelTool do
    it "returns an ok envelope with the model data" do
      allow(worker_manager).to receive(:model).with(name: "Widget").and_return(name: "Widget", columns: [])

      response = described_class.call(name: "Widget", server_context: server_context)
      payload = JSON.parse(response.content.first[:text])

      expect(response.error?).to be(false)
      expect(payload["data"]).to eq("name" => "Widget", "columns" => [])
    end

    it "returns an error envelope when the worker manager raises" do
      allow(worker_manager).to receive(:model).and_raise(Coatepec::Error.new(:invalid_model_name, "bad"))

      response = described_class.call(name: "bad name", server_context: server_context)
      payload = JSON.parse(response.content.first[:text])

      expect(response.error?).to be(true)
      expect(payload["error"]["code"]).to eq("invalid_model_name")
    end
  end

  describe Coatepec::MCP::FlakyCheckTool do
    it "returns an ok envelope with the flaky-check report" do
      allow(worker_manager).to receive(:check_flaky)
        .with(paths: ["spec/x_spec.rb"], example: nil, timeout_seconds: 120, runs: 5)
        .and_return(runs: 5, rounds: [], flaky_examples: [], consistently_failing: [])

      response = described_class.call(paths: ["spec/x_spec.rb"], server_context: server_context)
      payload = JSON.parse(response.content.first[:text])

      expect(response.error?).to be(false)
      expect(payload["data"]).to eq(
        "runs" => 5, "rounds" => [], "flaky_examples" => [], "consistently_failing" => []
      )
    end

    it "returns an error envelope when the worker manager raises" do
      allow(worker_manager).to receive(:check_flaky)
        .and_raise(Coatepec::Error.new(:flaky_check_budget_exceeded, "too much"))

      response = described_class.call(paths: ["spec/x_spec.rb"], server_context: server_context)
      payload = JSON.parse(response.content.first[:text])

      expect(response.error?).to be(true)
      expect(payload["error"]["code"]).to eq("flaky_check_budget_exceeded")
    end
  end

  it "registers all tools on a built server" do
    project = instance_double(Coatepec::Project, root: "/app")
    server = Coatepec::MCP.build_server(project: project, worker_manager: worker_manager)

    expect(server.tools.keys).to contain_exactly(
      "rails_spec_run", "rails_runtime_status", "rails_runtime_restart", "rails_spec_flaky_check", "rails_routes",
      "rails_model"
    )
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

    it "rejects unknown arguments to rails_runtime_restart" do
      expect { Coatepec::MCP::RuntimeRestartTool.input_schema.validate_arguments("oops" => 1) }
        .to raise_error(::MCP::Tool::InputSchema::ValidationError, /disallowed additional property/)
    end

    it "rejects unknown arguments to rails_spec_flaky_check" do
      expect do
        Coatepec::MCP::FlakyCheckTool.input_schema.validate_arguments("paths" => ["spec/x_spec.rb"], "oops" => 1)
      end.to raise_error(::MCP::Tool::InputSchema::ValidationError, /disallowed additional property/)
    end

    it "still accepts the documented rails_spec_run arguments" do
      expect { Coatepec::MCP::SpecRunTool.input_schema.validate_arguments("paths" => ["spec/x_spec.rb"]) }
        .not_to raise_error
    end
  end
end
