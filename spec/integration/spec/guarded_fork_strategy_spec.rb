# frozen_string_literal: true

require "spec_helper"

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
  end
end
