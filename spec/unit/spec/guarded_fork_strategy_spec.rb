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
