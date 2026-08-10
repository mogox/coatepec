# frozen_string_literal: true

require "spec_helper"

RSpec.describe Coatepec::WorkerManager, type: :integration do
  subject(:manager) { described_class.new(Coatepec::Project.new(FIXTURE_APP_ROOT)) }

  after { manager.stop }

  it "lazily boots the worker and reports status" do
    data = manager.status

    expect(data[:environment]).to eq("test")
    expect(data[:lifecycle_state]).to eq("ready")
  end

  it "restart! respawns the worker with a new pid/boot_id even when the old one is healthy" do
    before_status = manager.status

    after_status = manager.restart!

    expect(after_status[:pid]).not_to eq(before_status[:pid])
    expect(after_status[:boot_id]).not_to eq(before_status[:boot_id])
    expect(after_status[:lifecycle_state]).to eq("ready")
  end

  it "runs a spec through the warm worker" do
    data = manager.run_spec(paths: ["spec/passing_spec.rb"], example: nil, seed: nil, fail_fast: false,
                            timeout_seconds: 30)

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

  it "raises sidecar_restart_required when the worker is dead and Gemfile.lock changed" do
    manager.status # boots the worker and snapshots the Gemfile
    manager.stop   # the client is now dead, so ensure_worker! would rebaseline the snapshot

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

  it "raises sidecar_restart_required from restart! instead of silently rebaselining the snapshot" do
    manager.status # boots the worker and snapshots the Gemfile

    lockfile = File.join(FIXTURE_APP_ROOT, "Gemfile.lock")
    original = File.read(lockfile)
    sleep 0.01
    File.write(lockfile, "#{original}\n# touched")

    begin
      expect { manager.restart! }.to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:sidecar_restart_required) }
    ensure
      File.write(lockfile, original)
    end
  end

  it "recovers automatically when the worker process is killed out from under it" do
    before_status = manager.status
    Process.kill("KILL", before_status[:pid])
    sleep 0.3 # dies but is deliberately left unreaped -- the zombie case

    after_status = manager.status

    expect(after_status[:pid]).not_to eq(before_status[:pid])
    expect(after_status[:lifecycle_state]).to eq("ready")
  end
end
