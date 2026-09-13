# frozen_string_literal: true

require "spec_helper"
require "coatepec/mcp"

RSpec.describe "Coatepec MCP tools" do
  let(:worker_manager) { instance_double(Coatepec::WorkerManager) }
  let(:server_context) { { worker_manager: worker_manager, project_root: "/app" } }

  describe Coatepec::MCP::SpecRunTool do
    it "returns an ok envelope with the runner's data" do
      allow(worker_manager).to receive(:run_spec)
        .with(paths: ["spec/x_spec.rb"], example: nil, seed: nil, fail_fast: false, timeout_seconds: 120,
              include_passing: false, include_stdout: "failures")
        .and_return(status: "passed")

      response = described_class.call(paths: ["spec/x_spec.rb"], server_context: server_context)
      payload = JSON.parse(response.content.first[:text])

      expect(response.error?).to be(false)
      expect(payload["data"]).to eq("status" => "passed")
      expect(payload["meta"].keys).to eq(["duration_ms"])
    end

    it "returns an error envelope when the worker manager raises" do
      allow(worker_manager).to receive(:run_spec).and_raise(Coatepec::Error.new(:invalid_spec_path, "bad"))

      response = described_class.call(paths: ["../x"], server_context: server_context)
      payload = JSON.parse(response.content.first[:text])

      expect(response.error?).to be(true)
      expect(payload["error"]["code"]).to eq("invalid_spec_path")
    end

    it "forwards include_passing to the worker manager and defaults it to false" do
      allow(worker_manager).to receive(:run_spec).and_return(status: "passed", examples: [])

      described_class.call(paths: ["spec/x_spec.rb"], server_context: server_context)
      described_class.call(paths: ["spec/x_spec.rb"], include_passing: true, server_context: server_context)

      expect(worker_manager).to have_received(:run_spec).with(hash_including(include_passing: false)).ordered
      expect(worker_manager).to have_received(:run_spec).with(hash_including(include_passing: true)).ordered
    end

    it "declares include_passing as a boolean input" do
      expect(described_class.input_schema.to_h.dig(:properties, :include_passing)).to eq(type: "boolean")
    end

    it "forwards include_stdout to the worker manager and defaults it to failures" do
      allow(worker_manager).to receive(:run_spec).and_return(status: "passed", examples: [])

      described_class.call(paths: ["spec/x_spec.rb"], server_context: server_context)
      described_class.call(paths: ["spec/x_spec.rb"], include_stdout: "never", server_context: server_context)

      expect(worker_manager).to have_received(:run_spec).with(hash_including(include_stdout: "failures")).ordered
      expect(worker_manager).to have_received(:run_spec).with(hash_including(include_stdout: "never")).ordered
    end

    it "declares include_stdout as an enum input and documents it" do
      expect(described_class.input_schema.to_h.dig(:properties, :include_stdout))
        .to eq(type: "string", enum: %w[failures always never])
      expect(described_class.description).to include("include_stdout")
    end

    # Three benchmark sessions read failure_count against Minitest's own "0 failures, 5 errors" line and
    # suspected a bug; the description is the only place an MCP client can learn the vocabulary.
    it "explains that results use RSpec vocabulary" do
      expect(described_class.description).to include("RSpec vocabulary")
      expect(described_class.description).to include("failure_count")
      expect(described_class.description).to include("a skip is pending")
    end

    it "says there is no separate Minitest tool" do
      expect(described_class.description).to include("no separate Minitest tool")
    end
  end

  describe Coatepec::MCP::RuntimeStatusTool do
    it "returns an ok envelope with the worker status" do
      allow(worker_manager).to receive(:status).and_return(environment: "test")

      response = described_class.call(server_context: server_context)
      payload = JSON.parse(response.content.first[:text])

      expect(payload["data"]).to eq("environment" => "test", "project_root" => "/app")
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
    # The description is the whole agent-facing contract (the README is invisible to an MCP
    # client), so engine expansion and the `engine` field have to be stated there.
    it "announces engine expansion and the engine field in its description" do
      expect(described_class.description).to include("engines")
      expect(described_class.description).to include("engine field")
    end

    it "tells the client how to page through the results" do
      expect(described_class.description).to include("next_offset")
    end

    it "says engine routes are withheld by default, names the count field and declares the enum" do
      expect(described_class.description)
        .to start_with("Return a bounded, filterable list of the Rails app's routes, application routes only by " \
                       "default")
      expect(described_class.description).to include("engines_excluded")
      expect(described_class.input_schema.to_h.dig(:properties, :engines))
        .to eq(type: "string", enum: %w[include exclude only])
    end

    it "forwards engines to the worker manager and defaults it to exclude" do
      allow(worker_manager).to receive(:routes).and_return(items: [], matched: 0, limit: 100, offset: 0,
                                                           next_offset: nil)

      described_class.call(server_context: server_context)
      described_class.call(engines: "include", server_context: server_context)

      expect(worker_manager).to have_received(:routes).with(hash_including(engines: "exclude")).ordered
      expect(worker_manager).to have_received(:routes).with(hash_including(engines: "include")).ordered
    end

    it "returns an ok envelope with the routes data" do
      allow(worker_manager).to receive(:routes)
        .with(query: "widgets", limit: 50, offset: 0, engines: "exclude")
        .and_return(items: [], matched: 0, limit: 50, offset: 0)

      response = described_class.call(query: "widgets", limit: 50, offset: 0, server_context: server_context)
      payload = JSON.parse(response.content.first[:text])

      expect(response.error?).to be(false)
      expect(payload["data"]).to eq("items" => [], "matched" => 0, "limit" => 50, "offset" => 0)
    end

    it "defaults limit to 100" do
      allow(worker_manager).to receive(:routes).and_return(items: [], matched: 0, limit: 100, offset: 0,
                                                           next_offset: nil)

      described_class.call(server_context: server_context)

      expect(worker_manager).to have_received(:routes).with(query: nil, limit: 100, offset: 0, engines: "exclude")
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
    it "explains validator de-duplication and option truncation in its description" do
      expect(described_class.description).to include("distinct validators")
      expect(described_class.description).to include("_truncated")
    end

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

  describe Coatepec::MCP::ControllerTool do
    it "is registered under the rails_controller tool name" do
      expect(described_class.tool_name).to eq("rails_controller")
    end

    it "returns an ok envelope with the controller data" do
      allow(worker_manager).to receive(:controller)
        .with(name: "WidgetsController")
        .and_return(name: "WidgetsController", actions: [], unroutable_actions: [])

      response = described_class.call(name: "WidgetsController", server_context: server_context)
      payload = JSON.parse(response.content.first[:text])

      expect(response.error?).to be(false)
      expect(payload["data"])
        .to eq("name" => "WidgetsController", "actions" => [], "unroutable_actions" => [])
    end

    it "returns an error envelope when the worker manager raises" do
      allow(worker_manager).to receive(:controller)
        .and_raise(Coatepec::Error.new(:invalid_controller_name, "bad"))

      response = described_class.call(name: "bad name", server_context: server_context)
      payload = JSON.parse(response.content.first[:text])

      expect(response.error?).to be(true)
      expect(payload["error"]["code"]).to eq("invalid_controller_name")
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
      "rails_spec_run", "rails_runtime_status", "rails_runtime_restart",
      "rails_spec_flaky_check", "rails_routes", "rails_model", "rails_controller"
    )
  end

  describe "input schema strictness" do
    it "rejects unknown arguments to rails_spec_run" do
      expect { Coatepec::MCP::SpecRunTool.input_schema.validate_arguments("paths" => ["spec/x_spec.rb"], "oops" => 1) }
        .to raise_error(::MCP::Tool::InputSchema::ValidationError, /disallowed additional property/)
    end

    it "rejects a boolean include_stdout on rails_spec_run" do
      expect do
        Coatepec::MCP::SpecRunTool.input_schema
                                  .validate_arguments("paths" => ["spec/x_spec.rb"], "include_stdout" => false)
      end.to raise_error(::MCP::Tool::InputSchema::ValidationError)
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

    it "rejects an engines value outside include/exclude/only on rails_routes" do
      expect { Coatepec::MCP::RoutesTool.input_schema.validate_arguments("engines" => "some") }
        .to raise_error(::MCP::Tool::InputSchema::ValidationError)
    end

    it "still accepts the documented rails_spec_run arguments" do
      expect { Coatepec::MCP::SpecRunTool.input_schema.validate_arguments("paths" => ["spec/x_spec.rb"]) }
        .not_to raise_error
    end
  end
end
