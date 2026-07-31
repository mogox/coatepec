# frozen_string_literal: true

require "spec_helper"

RSpec.describe Coatepec::WorkerManager, type: :integration do
  subject(:manager) { described_class.new(Coatepec::Project.new(FIXTURE_APP_ROOT)) }

  it "lazily boots the worker and reports status" do
    data = manager.status

    expect(data[:environment]).to eq("test")
    expect(data[:lifecycle_state]).to eq("ready")
  end

  it "runs a spec through the warm worker" do
    data = manager.run_spec(paths: ["spec/passing_spec.rb"], example: nil, seed: nil, fail_fast: false, timeout_seconds: 30)

    expect(data[:status]).to eq("passed")
  end

  it "raises sidecar_restart_required when Gemfile.lock changes after boot" do
    manager.status # boots the worker and snapshots the Gemfile

    lockfile = File.join(FIXTURE_APP_ROOT, "Gemfile.lock")
    original = File.read(lockfile)
    sleep 0.01
    File.write(lockfile, "#{original}\n# touched")

    begin
      expect { manager.status }.to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:sidecar_restart_required) }
    ensure
      File.write(lockfile, original)
    end
  end
end
