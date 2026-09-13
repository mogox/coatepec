# frozen_string_literal: true

require "spec_helper"

RSpec.describe Coatepec::Spec::GuardedForkStrategy do
  subject(:strategy) do
    described_class.new(FIXTURE_APP_ROOT, project: project, rails_runtime: rails_runtime)
  end

  let(:rails_runtime) do
    instance_double(Coatepec::Worker::RailsRuntime, post_boot_thread_count: 5, loaded_gem_names: %w[rails rspec-core])
  end
  let(:project_config) { instance_double(Coatepec::ProjectConfig, macos_fork_unsafe_gems: []) }
  let(:project) { instance_double(Coatepec::Project, config: project_config) }

  describe "#guard_passes?" do
    it "passes when the live thread count matches the post-boot baseline" do
      allow(Thread).to receive(:list).and_return(Array.new(5))

      expect(strategy.send(:guard_passes?)).to be(true)
    end

    it "passes when thread count is within tolerance (+1) of the baseline" do
      allow(Thread).to receive(:list).and_return(Array.new(6))

      expect(strategy.send(:guard_passes?)).to be(true)
    end

    it "fails when thread count exceeds the baseline beyond tolerance" do
      allow(Thread).to receive(:list).and_return(Array.new(7))

      expect(strategy.send(:guard_passes?)).to be(false)
    end

    it "fails when a loaded gem is on the built-in denylist" do
      stub_const("Coatepec::Spec::GuardedForkStrategy::BUILTIN_UNSAFE_GEMS", %w[rails])
      allow(Thread).to receive(:list).and_return(Array.new(5))

      expect(strategy.send(:guard_passes?)).to be(false)
    end

    it "fails when a loaded gem is on the project's configured denylist" do
      allow(Thread).to receive(:list).and_return(Array.new(5))
      allow(project_config).to receive(:macos_fork_unsafe_gems).and_return(%w[rspec-core])

      expect(strategy.send(:guard_passes?)).to be(false)
    end

    it "passes when there is no rails_runtime to check against" do
      bare_strategy = described_class.new(FIXTURE_APP_ROOT)

      expect(bare_strategy.send(:guard_passes?)).to be(true)
    end
  end

  describe "#retry_after_crash" do
    let(:spawn_strategy) { instance_double(Coatepec::Spec::SpawnStrategy, run: { status: "passed" }) }

    before { strategy.instance_variable_set(:@spawn_strategy, spawn_strategy) }

    def retry_after(started_at, crashed = { stderr: "" })
      strategy.send(:retry_after_crash, ["spec/passing_spec.rb"], 30, started_at, crashed,
                    { include_passing: false, include_stdout: "failures" })
    end

    it "passes the spawn fallback the budget left after the fork attempt" do
      retry_after(Process.clock_gettime(Process::CLOCK_MONOTONIC) - 10)

      expect(spawn_strategy).to have_received(:run) do |_args, timeout|
        expect(timeout).to be_within(1).of(20)
      end
    end

    it "floors the remaining budget so an exhausted one can't guarantee a timeout kill" do
      retry_after(Process.clock_gettime(Process::CLOCK_MONOTONIC) - 100)

      expect(spawn_strategy).to have_received(:run)
        .with(anything, described_class::MIN_RETRY_TIMEOUT_SECONDS, include_passing: false, include_stdout: "failures")
    end

    it "carries the crashed fork's stderr through on the result" do
      result = retry_after(Process.clock_gettime(Process::CLOCK_MONOTONIC), { stderr: "objc[1]: +[__NSCFTimer ...]" })

      expect(result[:crashed_fork_stderr]).to eq("objc[1]: +[__NSCFTimer ...]")
    end

    it "truncates oversized crash stderr to its tail" do
      oversized = "#{"x" * described_class::MAX_CRASH_STDERR_BYTES}TAIL"

      result = retry_after(Process.clock_gettime(Process::CLOCK_MONOTONIC), { stderr: oversized })

      expect(result[:crashed_fork_stderr].bytesize).to eq(described_class::MAX_CRASH_STDERR_BYTES)
      expect(result[:crashed_fork_stderr]).to end_with("TAIL")
    end
  end

  describe "#crashed?" do
    it "is true for a child that died from SIGABRT" do
      result = { signaled: true, termsig: Signal.list["ABRT"] }

      expect(strategy.send(:crashed?, result)).to be(true)
    end

    it "is true for a child that died from SIGSEGV" do
      result = { signaled: true, termsig: Signal.list["SEGV"] }

      expect(strategy.send(:crashed?, result)).to be(true)
    end

    it "is false for a child that exited normally" do
      result = { signaled: false, termsig: nil }

      expect(strategy.send(:crashed?, result)).to be(false)
    end

    it "is false for a child killed by a non-crash signal" do
      result = { signaled: true, termsig: Signal.list["TERM"] }

      expect(strategy.send(:crashed?, result)).to be(false)
    end
  end
end
