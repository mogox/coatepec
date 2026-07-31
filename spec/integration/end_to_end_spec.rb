# frozen_string_literal: true

require "spec_helper"

RSpec.describe "coatepec end-to-end", type: :integration do
  def send_request(stdin, id, method, params = {})
    stdin.puts(JSON.generate(jsonrpc: "2.0", id: id, method: method, params: params))
  end

  def read_response(stdout)
    JSON.parse(stdout.gets)
  end

  it "serves rails_runtime_status and rails_spec_run over stdio" do
    # NOTE: unlike the worker subprocess (which repoints BUNDLE_GEMFILE at the
    # target Rails app), the top-level `coatepec` process itself must keep
    # running under *coatepec's own* Gemfile (already the ambient
    # BUNDLE_GEMFILE under `bundle exec rspec`) so it can `require "mcp"`.
    # The `--root` flag alone tells it which app to manage; WorkerManager
    # repoints BUNDLE_GEMFILE only for the worker child it spawns internally.
    coatepec_exe = File.expand_path("../../exe/coatepec", __dir__)
    stdin, stdout, wait_thr = Open3.popen2(
      RbConfig.ruby, coatepec_exe, "--root", FIXTURE_APP_ROOT
    )

    begin
      send_request(stdin, 1, "initialize", {
        protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "e2e", version: "1.0" }
      })
      init_response = read_response(stdout)
      expect(init_response["result"]["serverInfo"]["name"]).to eq("coatepec")

      send_request(stdin, 2, "tools/call", { name: "rails_runtime_status", arguments: {} })
      status_response = read_response(stdout)
      status_payload = JSON.parse(status_response["result"]["content"].first["text"])
      expect(status_payload["data"]["environment"]).to eq("test")

      send_request(stdin, 3, "tools/call", { name: "rails_spec_run", arguments: { paths: ["spec/passing_spec.rb"] } })
      spec_response = read_response(stdout)
      spec_payload = JSON.parse(spec_response["result"]["content"].first["text"])
      expect(spec_payload["data"]["status"]).to eq("passed")
    ensure
      stdin.close
      stdout.close
      # The child may have already exited cleanly (its stdin hit EOF once we
      # closed our end above) and been reaped by Open3's internal detach
      # thread by the time we get here, so tolerate a race on the kill.
      begin
        Process.kill("TERM", wait_thr.pid)
      rescue Errno::ESRCH
        nil
      end
      wait_thr.join(5)
    end
  end
end
