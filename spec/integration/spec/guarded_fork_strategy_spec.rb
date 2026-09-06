# frozen_string_literal: true

require "spec_helper"
require "fileutils"

RSpec.describe Coatepec::Spec::GuardedForkStrategy, type: :integration do
  def run_in_worker(ruby_tail)
    lib_path = File.expand_path("../../../lib", __dir__)
    script = <<~RUBY
      $LOAD_PATH.unshift(#{lib_path.inspect})
      require "coatepec"
      # Production only ever reaches a strategy's #run via
      # Coatepec::Spec::Runner#run, which requires "rspec/core" first. This
      # script calls GuardedForkStrategy#run directly (bypassing Runner), so
      # it must do that require itself or the forked child's
      # RSpec::Core::Runner.run call raises NameError.
      require "rspec/core"
      runtime = Coatepec::Worker::RailsRuntime.new(#{FIXTURE_APP_ROOT.inspect})
      runtime.boot!
      project = Coatepec::Project.new(#{FIXTURE_APP_ROOT.inspect})
      #{ruby_tail}
    RUBY
    run_in_fixture_app(script)
  end

  it "forks and reports execution_mode fork when the guard passes" do
    stdout, stderr, status = run_in_worker(<<~RUBY)
      strategy = Coatepec::Spec::GuardedForkStrategy.new(#{FIXTURE_APP_ROOT.inspect}, project: project, rails_runtime: runtime)
      result = strategy.run(["spec/passing_spec.rb"], 30)
      puts JSON.generate(result)
    RUBY

    expect(status).to be_success, stderr
    result = JSON.parse(stdout.lines.last)

    expect(result["status"]).to eq("passed")
    expect(result["execution_mode"]).to eq("fork")
  end

  it "runs a Minitest selection through the guarded fork and through the spawn fallback" do
    stdout, stderr, status = run_in_worker(<<~RUBY)
      require "minitest"
      adapter = Coatepec::TestUnit::Adapter.new(#{FIXTURE_APP_ROOT.inspect})
      forked = Coatepec::Spec::GuardedForkStrategy
                 .new(#{FIXTURE_APP_ROOT.inspect}, adapter: adapter, project: project, rails_runtime: runtime)
                 .run(["test/models/passing_test.rb:9"], 30)
      fake_runtime = Object.new
      def fake_runtime.post_boot_thread_count = -1
      def fake_runtime.loaded_gem_names = []
      spawned = Coatepec::Spec::GuardedForkStrategy
                  .new(#{FIXTURE_APP_ROOT.inspect}, adapter: adapter, project: project, rails_runtime: fake_runtime)
                  .run(["test/models/passing_test.rb:9"], 30)
      puts JSON.generate(forked: forked, spawned: spawned)
    RUBY

    expect(status).to be_success, stderr
    result = JSON.parse(stdout.lines.last)

    expect(result["forked"]["execution_mode"]).to eq("fork")
    expect(result["forked"]["status"]).to eq("passed"), result["forked"]["stderr"]
    expect(result["forked"]["examples"].map { |e| e["id"] }).to eq(["PassingTest#test_reaches_the_database"])
    expect(result["spawned"]["execution_mode"]).to eq("spawn_fallback")
    expect(result["spawned"]["examples"].map { |e| e["id"] }).to eq(["PassingTest#test_reaches_the_database"])
  end

  it "falls back to spawn without forking when the thread-count guard fails" do
    stdout, stderr, status = run_in_worker(<<~RUBY)
      fake_runtime = Object.new
      # A live process always has at least 1 thread (the main thread), so a
      # baseline of 0 would only fail the +1-tolerance guard on a machine
      # that happens to run >1 thread post-boot. -1 guarantees the guard
      # fails regardless of how many threads this environment's boot leaves
      # running.
      def fake_runtime.post_boot_thread_count = -1
      def fake_runtime.loaded_gem_names = []

      strategy = Coatepec::Spec::GuardedForkStrategy.new(#{FIXTURE_APP_ROOT.inspect}, project: project, rails_runtime: fake_runtime)
      result = strategy.run(["spec/passing_spec.rb"], 30)
      puts JSON.generate(result)
    RUBY

    expect(status).to be_success, stderr
    result = JSON.parse(stdout.lines.last)

    expect(result["status"]).to eq("passed")
    expect(result["execution_mode"]).to eq("spawn_fallback")
  end

  it "recovers via spawn when the forked child crashes, reporting execution_mode spawn_after_crash" do
    stdout, stderr, status = run_in_worker(<<~RUBY)
      module RSpec
        module Core
          class Runner
            def self.run(*)
              $stderr.puts "COATEPEC_CRASH_DIAGNOSTIC"
              Process.kill("ABRT", Process.pid)
            end
          end
        end
      end

      strategy = Coatepec::Spec::GuardedForkStrategy.new(#{FIXTURE_APP_ROOT.inspect}, project: project, rails_runtime: runtime)
      result = strategy.run(["spec/passing_spec.rb"], 30)
      puts JSON.generate(result)
    RUBY

    expect(status).to be_success, stderr
    result = JSON.parse(stdout.lines.last)

    # The crash happens inside the (monkeypatched) forked child; recovery
    # re-runs via a fresh `bundle exec rspec` subprocess that does NOT
    # inherit the parent's in-memory monkeypatch, so this result is real.
    expect(result["status"]).to eq("passed")
    expect(result["execution_mode"]).to eq("spawn_after_crash")
    # The crashed child's stderr is the only place a real macOS crash report
    # would land, so it must survive the fallback rather than be discarded.
    expect(result["crashed_fork_stderr"]).to include("COATEPEC_CRASH_DIAGNOSTIC")
  end

  it "gives the post-crash spawn only the timeout budget the fork attempt left" do
    stdout, stderr, status = run_in_worker(<<~RUBY)
      module RSpec
        module Core
          class Runner
            def self.run(*)
              sleep 3
              Process.kill("ABRT", Process.pid)
            end
          end
        end
      end

      module Coatepec
        module Spec
          class SpawnStrategy
            alias_method :run_without_spy, :run
            def run(args, timeout_seconds)
              $observed_timeout = timeout_seconds
              run_without_spy(args, timeout_seconds)
            end
          end
        end
      end

      strategy = Coatepec::Spec::GuardedForkStrategy.new(#{FIXTURE_APP_ROOT.inspect}, project: project, rails_runtime: runtime)
      result = strategy.run(["spec/passing_spec.rb"], 30)
      puts JSON.generate(result.merge(observed_timeout: $observed_timeout))
    RUBY

    expect(status).to be_success, stderr
    result = JSON.parse(stdout.lines.last)

    expect(result["execution_mode"]).to eq("spawn_after_crash")
    # The fork attempt burned ~3s of the 30s budget; the retry must get the
    # remainder, not a fresh 30s -- WorkerManager only allows the whole
    # dispatch timeout_seconds + 10 before it restarts the warm worker.
    expect(result["observed_timeout"]).to be < 30
    expect(result["observed_timeout"]).to be > 20
  end

  it "falls back to spawn when Process.fork itself raises" do
    stdout, stderr, status = run_in_worker(<<~RUBY)
      # Errno::EAGAIN/ENOMEM under process-table pressure: fork fails before
      # any child exists, and that must not escape as an :internal_error.
      def Process.fork(*)
        raise Errno::EAGAIN
      end

      strategy = Coatepec::Spec::GuardedForkStrategy.new(#{FIXTURE_APP_ROOT.inspect}, project: project, rails_runtime: runtime)
      result = strategy.run(["spec/passing_spec.rb"], 30)
      puts JSON.generate(result)
    RUBY

    expect(status).to be_success, stderr
    result = JSON.parse(stdout.lines.last)

    expect(result["status"]).to eq("passed")
    expect(result["summary"]["example_count"]).to eq(1)
    expect(result["execution_mode"]).to eq("spawn_fallback")
  end

  describe "wired through Worker::Server" do
    # Written into the shared fixture app rather than a copy so the run uses
    # the app's real installed bundle; removed after so it can't leak into
    # the specs that share this fixture.
    let(:config_path) { File.join(FIXTURE_APP_ROOT, ".coatepec.yml") }

    before { File.write(config_path, "macos_fork: true\n") }
    after { FileUtils.rm_f(config_path) }

    it "reports execution_mode fork through a real NDJSON spec_run round-trip" do
      stdout, stderr, status = run_in_fixture_app(<<~RUBY)
        $LOAD_PATH.unshift(#{File.expand_path("../../../lib", __dir__).inspect})
        require "coatepec"

        # Plain assignment, not an RSpec stub: this runs in a spawned
        # subprocess with no rspec-mocks session. RbConfig::CONFIG is a
        # mutable Hash, so this is all a darwin gate ever reads.
        RbConfig::CONFIG["host_os"] = "darwin24"

        to_server_r, to_server_w = IO.pipe
        from_server_r, from_server_w = IO.pipe
        client = Coatepec::Protocol.new(input: from_server_r, output: to_server_w)

        client.write(id: 1, command: "spec_run", args: { paths: ["spec/passing_spec.rb"] })
        to_server_w.close

        # Reads concurrently so a response larger than the pipe buffer can't
        # deadlock the server; started before boot! so RailsRuntime's
        # post-boot thread baseline counts it and the guard still passes.
        response = nil
        reader = Thread.new { response = client.read }

        Coatepec::Worker::Server.new(#{FIXTURE_APP_ROOT.inspect}, input: to_server_r, protocol_output: from_server_w).run
        from_server_w.close
        reader.join

        puts JSON.generate(response)
      RUBY

      expect(status).to be_success, stderr
      response = JSON.parse(stdout.lines.last)

      expect(response["ok"]).to be(true), stdout
      expect(response["data"]["status"]).to eq("passed")
      expect(response["data"]["execution_mode"]).to eq("fork")
    end
  end
end
