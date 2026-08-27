# frozen_string_literal: true

require "spec_helper"

RSpec.describe "coatepec-worker executable", type: :integration do
  def spawn_worker
    lib_path = File.expand_path("../../../lib", __dir__)
    to_worker_r, to_worker_w = IO.pipe
    from_worker_r, from_worker_w = IO.pipe

    pid = spawn_worker_process(lib_path, to_worker_r, from_worker_w)
    to_worker_r.close
    from_worker_w.close

    [pid, Coatepec::Protocol.new(input: from_worker_r, output: to_worker_w)]
  end

  def spawn_worker_process(lib_path, to_worker_r, from_worker_w)
    worker_exe = File.expand_path("../../../exe/coatepec-worker", __dir__)
    # Mirrors Worker::Client#spawn_worker's Bundler.with_unbundled_env: this
    # process runs under coatepec's own bundle, whose GEM_PATH must not leak
    # into the fixture app's separately-installed gems.
    Bundler.with_unbundled_env do
      Process.spawn(
        { "BUNDLE_GEMFILE" => File.join(FIXTURE_APP_ROOT, "Gemfile"), "RUBYLIB" => lib_path },
        RbConfig.ruby, worker_exe, FIXTURE_APP_ROOT,
        in: to_worker_r, out: from_worker_w, err: :err, chdir: FIXTURE_APP_ROOT
      )
    end
  end

  after do
    Process.kill("TERM", @pid) if @pid
    Process.wait(@pid)
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  end

  it "answers a status command after lazily booting Rails" do
    @pid, protocol = spawn_worker

    protocol.write(id: 1, command: "status", args: {})
    response = protocol.read

    expect(response[:id]).to eq(1)
    expect(response[:ok]).to be(true)
    expect(response[:data][:rails_version]).to match(/\A(7\.1|8\.1)\./)
    expect(response[:data][:environment]).to eq("test")
  end

  it "answers a spec_run command" do
    @pid, protocol = spawn_worker

    protocol.write(id: 1, command: "spec_run", args: { paths: ["spec/passing_spec.rb"] })
    response = protocol.read

    expect(response[:ok]).to be(true)
    expect(response[:data][:status]).to eq("passed")
    # The forked/spawned child's stdout must be captured on its own pipe, not
    # swallowed into stderr or written onto the NDJSON protocol's fd 1.
    expect(response[:data][:stdout]).to include("1 example, 0 failures")
  end

  it "answers with a structured error for an invalid spec path" do
    @pid, protocol = spawn_worker

    protocol.write(id: 1, command: "spec_run", args: { paths: ["../Gemfile"] })
    response = protocol.read

    expect(response[:ok]).to be(false)
    expect(response[:error][:code]).to eq("invalid_spec_path")
  end

  it "keeps dispatching correctly once every command is wrapped in Rails' reloader" do
    @pid, protocol = spawn_worker

    protocol.write(id: 1, command: "status", args: {})
    first = protocol.read
    protocol.write(id: 2, command: "status", args: {})
    second = protocol.read

    expect(first[:ok]).to be(true)
    expect(second[:ok]).to be(true)
    expect(second[:data][:boot_id]).to eq(first[:data][:boot_id])
  end

  it "answers a routes command" do
    @pid, protocol = spawn_worker

    protocol.write(id: 1, command: "routes", args: { query: "widgets" })
    response = protocol.read

    expect(response[:ok]).to be(true)
    expect(response[:data][:items]).not_to be_empty
    expect(response[:data][:items].first[:controller]).to eq("widgets")
  end

  it "answers a model command" do
    @pid, protocol = spawn_worker

    protocol.write(id: 1, command: "model", args: { name: "Widget" })
    response = protocol.read

    expect(response[:ok]).to be(true)
    expect(response[:data][:name]).to eq("Widget")
    expect(response[:data][:columns]).not_to be_empty
    # enums[].values' keys are data-driven (enum label strings from the
    # target app's own code), unlike every other field here, which is keyed
    # off a fixed schema-defined name (e.g. column.name). This is the field
    # that actually exercises Protocol#read's symbolize_names: true behavior
    # across the real NDJSON round-trip.
    status_enum = response[:data][:enums].find { |e| e[:name] == "status" }
    expect(status_enum[:values]).to eq(draft: 0, published: 1)
  end

  it "answers with a structured error for an invalid model name" do
    @pid, protocol = spawn_worker

    protocol.write(id: 1, command: "model", args: { name: "not_a_constant" })
    response = protocol.read

    expect(response[:ok]).to be(false)
    expect(response[:error][:code]).to eq("invalid_model_name")
  end

  it "answers a job command" do
    @pid, protocol = spawn_worker

    protocol.write(id: 1, command: "job", args: { name: "WidgetIndexJob" })
    response = protocol.read

    expect(response[:ok]).to be(true)
    expect(response[:data][:name]).to eq("WidgetIndexJob")
    expect(response[:data][:queue_name]).to eq("low_priority")
    expect(response[:data][:rescued_exceptions]).not_to be_empty
  end

  it "answers with a structured error for an invalid job name" do
    @pid, protocol = spawn_worker

    protocol.write(id: 1, command: "job", args: { name: "not_a_constant" })
    response = protocol.read

    expect(response[:ok]).to be(false)
    expect(response[:error][:code]).to eq("invalid_job_name")
  end
end
