# frozen_string_literal: true

require "spec_helper"
require "coatepec/worker/change_detector"
require "tmpdir"
require "fileutils"

RSpec.describe Coatepec::Worker::ChangeDetector do
  around do |example|
    Dir.mktmpdir do |dir|
      @tmp = dir
      FileUtils.mkdir_p(File.join(@tmp, "config/environments"))
      FileUtils.mkdir_p(File.join(@tmp, "config/initializers"))
      File.write(File.join(@tmp, "Gemfile"), "a")
      File.write(File.join(@tmp, "Gemfile.lock"), "a")
      File.write(File.join(@tmp, "config/boot.rb"), "a")
      File.write(File.join(@tmp, "config/application.rb"), "a")
      File.write(File.join(@tmp, "config/environment.rb"), "a")
      File.write(File.join(@tmp, "config/environments/test.rb"), "a")
      example.run
    end
  end

  subject(:detector) { described_class.new(@tmp) }

  it "returns no restart reason when nothing changed" do
    snapshot = detector.snapshot

    expect(detector.restart_reason(snapshot)).to be_nil
  end

  it "flags sidecar_restart_required when Gemfile.lock changes" do
    snapshot = detector.snapshot
    sleep 0.01
    File.write(File.join(@tmp, "Gemfile.lock"), "b")

    expect(detector.restart_reason(snapshot)).to eq(:sidecar_restart_required)
  end

  it "flags worker_restart_required when a boot file changes" do
    snapshot = detector.snapshot
    sleep 0.01
    File.write(File.join(@tmp, "config/environment.rb"), "b")

    expect(detector.restart_reason(snapshot)).to eq(:worker_restart_required)
  end

  it "flags worker_restart_required when an initializer is added" do
    snapshot = detector.snapshot
    sleep 0.01
    File.write(File.join(@tmp, "config/initializers/new.rb"), "a")

    expect(detector.restart_reason(snapshot)).to eq(:worker_restart_required)
  end

  it "prefers sidecar_restart_required when both bundle and boot files change" do
    snapshot = detector.snapshot
    sleep 0.01
    File.write(File.join(@tmp, "Gemfile"), "b")
    File.write(File.join(@tmp, "config/boot.rb"), "b")

    expect(detector.restart_reason(snapshot)).to eq(:sidecar_restart_required)
  end
end
