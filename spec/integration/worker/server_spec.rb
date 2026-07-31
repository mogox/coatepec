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
end
