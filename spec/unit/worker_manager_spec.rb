# frozen_string_literal: true

require "spec_helper"

RSpec.describe Coatepec::WorkerManager do
  # These examples stub Worker::Client.spawn entirely, so no real worker
  # process is ever started -- WorkerManager's own dispatch/retry/restart
  # logic is what's under test here, not the worker itself (real end-to-end
  # behavior is covered in spec/integration/worker_manager_spec.rb).
  subject(:manager) { described_class.new(Coatepec::Project.new(FIXTURE_APP_ROOT)) }

  describe "#status retry behavior" do
    it "restarts the worker once and retries when the client raises a raw SystemCallError" do
      dead_client = instance_double(Coatepec::Worker::Client, alive?: true, stop: nil)
      allow(dead_client).to receive(:request).and_raise(Errno::EPIPE)
      healthy_client = instance_double(Coatepec::Worker::Client, alive?: true, stop: nil,
                                                                 request: { environment: "test" })
      allow(Coatepec::Worker::Client).to receive(:spawn).and_return(dead_client, healthy_client)

      expect(manager.status).to eq(environment: "test")
      expect(Coatepec::Worker::Client).to have_received(:spawn).twice
    end

    it "raises worker_disconnected if the retry also raises" do
      dead_client = instance_double(Coatepec::Worker::Client, alive?: true, stop: nil)
      allow(dead_client).to receive(:request).and_raise(Errno::EPIPE)
      allow(Coatepec::Worker::Client).to receive(:spawn).and_return(dead_client)

      expect { manager.status }.to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:worker_disconnected) }
    end

    it "still retries once for the original DisconnectedError case" do
      dead_client = instance_double(Coatepec::Worker::Client, alive?: true, stop: nil)
      allow(dead_client).to receive(:request).and_raise(Coatepec::Worker::Client::DisconnectedError, "gone")
      healthy_client = instance_double(Coatepec::Worker::Client, alive?: true, stop: nil,
                                                                 request: { environment: "test" })
      allow(Coatepec::Worker::Client).to receive(:spawn).and_return(dead_client, healthy_client)

      expect(manager.status).to eq(environment: "test")
    end
  end

  describe "#run_spec" do
    it "dispatches include_passing, defaulting it to false" do
      client = instance_double(Coatepec::Worker::Client, alive?: true, stop: nil, request: { status: "passed" })
      allow(Coatepec::Worker::Client).to receive(:spawn).and_return(client)

      manager.run_spec(paths: ["spec/models/widget_spec.rb"], example: nil, seed: nil, fail_fast: false,
                       timeout_seconds: 30)
      manager.run_spec(paths: ["spec/models/widget_spec.rb"], example: nil, seed: nil, fail_fast: false,
                       timeout_seconds: 30, include_passing: true)

      expect(client).to have_received(:request)
        .with("spec_run", hash_including(include_passing: false), timeout: 40).ordered
      expect(client).to have_received(:request)
        .with("spec_run", hash_including(include_passing: true), timeout: 40).ordered
    end

    it "dispatches include_stdout, defaulting it to failures" do
      client = instance_double(Coatepec::Worker::Client, alive?: true, stop: nil, request: { status: "passed" })
      allow(Coatepec::Worker::Client).to receive(:spawn).and_return(client)

      manager.run_spec(paths: ["spec/models/widget_spec.rb"], example: nil, seed: nil, fail_fast: false,
                       timeout_seconds: 30)
      manager.run_spec(paths: ["spec/models/widget_spec.rb"], example: nil, seed: nil, fail_fast: false,
                       timeout_seconds: 30, include_stdout: "never")

      expect(client).to have_received(:request)
        .with("spec_run", hash_including(include_stdout: "failures"), timeout: 40).ordered
      expect(client).to have_received(:request)
        .with("spec_run", hash_including(include_stdout: "never"), timeout: 40).ordered
    end
  end

  describe "#routes" do
    it "dispatches engines, defaulting it to exclude" do
      client = instance_double(Coatepec::Worker::Client, alive?: true, stop: nil, request: { rows: [] })
      allow(Coatepec::Worker::Client).to receive(:spawn).and_return(client)

      manager.routes(query: "talk")
      manager.routes(query: "talk", engines: "only")

      expect(client).to have_received(:request)
        .with("routes", { query: "talk", limit: 100, offset: 0, engines: "exclude" }, timeout: 30).ordered
      expect(client).to have_received(:request)
        .with("routes", { query: "talk", limit: 100, offset: 0, engines: "only" }, timeout: 30).ordered
    end
  end

  describe "#model" do
    it "dispatches fields, defaulting it to nil (counts only)" do
      client = instance_double(Coatepec::Worker::Client, alive?: true, stop: nil, request: { name: "Widget" })
      allow(Coatepec::Worker::Client).to receive(:spawn).and_return(client)

      manager.model(name: "Widget")
      manager.model(name: "Widget", fields: ["enums"])

      expect(client).to have_received(:request)
        .with("model", { name: "Widget", fields: nil }, timeout: 30).ordered
      expect(client).to have_received(:request)
        .with("model", { name: "Widget", fields: ["enums"] }, timeout: 30).ordered
    end
  end

  describe "#check_flaky" do
    it "scales its dispatch timeout slack with runs, on top of the flat base" do
      client = instance_double(Coatepec::Worker::Client, alive?: true, stop: nil, request: { rounds: [] })
      allow(Coatepec::Worker::Client).to receive(:spawn).and_return(client)

      manager.check_flaky(paths: ["spec/models/widget_spec.rb"], example: nil, timeout_seconds: 30, runs: 20)

      # (timeout_seconds * runs) + (2 * runs) + 10 == (30 * 20) + (2 * 20) + 10 == 650
      expect(client).to have_received(:request).with(
        "flaky_check",
        hash_including(timeout_seconds: 30, runs: 20),
        timeout: 650
      )
    end
  end

  describe "#restart!" do
    it "unconditionally spawns a fresh client even when the current one reports alive" do
      old_client = instance_double(Coatepec::Worker::Client, alive?: true, stop: nil)
      new_client = instance_double(Coatepec::Worker::Client, alive?: true, stop: nil,
                                                             request: { environment: "test", boot_id: "fresh" })
      allow(Coatepec::Worker::Client).to receive(:spawn).and_return(old_client, new_client)
      allow(old_client).to receive(:request).and_return({ environment: "test" })

      manager.status # boots old_client first, establishing @client
      result = manager.restart!

      expect(old_client).to have_received(:stop)
      expect(result).to eq(environment: "test", boot_id: "fresh")
      expect(Coatepec::Worker::Client).to have_received(:spawn).twice
    end
  end
end
