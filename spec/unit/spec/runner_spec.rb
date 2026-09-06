# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Coatepec::Spec::Runner do
  subject(:runner) { described_class.new(FIXTURE_APP_ROOT) }

  describe "framework dispatch" do
    it "picks the RSpec adapter for :rspec" do
      expect(runner.send(:adapter_for, :rspec)).to be_a(Coatepec::Spec::RSpecAdapter)
    end

    it "picks the Minitest adapter for :minitest" do
      expect(runner.send(:adapter_for, :minitest)).to be_a(Coatepec::TestUnit::Adapter)
    end

    it "validates paths before requiring any framework, so a bad path reports invalid_spec_path" do
      allow_any_instance_of(Coatepec::Spec::RSpecAdapter)
        .to receive(:require_framework!).and_raise("must not be called")

      expect { runner.run(paths: ["../Gemfile"]) }
        .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:invalid_spec_path) }
    end
  end

  describe "platform gate" do
    def stub_host_os(value)
      allow(RbConfig::CONFIG).to receive(:[]).and_call_original
      allow(RbConfig::CONFIG).to receive(:[]).with("host_os").and_return(value)
    end

    it "forks on Linux" do
      stub_host_os("linux-gnu")

      expect(runner.send(:strategy_class)).to eq(Coatepec::Spec::ForkStrategy)
    end

    it "spawns on macOS" do
      stub_host_os("darwin24")

      expect(runner.send(:strategy_class)).to eq(Coatepec::Spec::SpawnStrategy)
    end

    it "raises unsupported_platform on Windows" do
      stub_host_os("mswin64")

      expect { runner.send(:strategy_class) }
        .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:unsupported_platform) }
    end

    it "uses GuardedForkStrategy on macOS when the project's .coatepec.yml enables macos_fork" do
      stub_host_os("darwin24")
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "Gemfile"), "source 'https://rubygems.org'\n")
        File.write(File.join(dir, ".coatepec.yml"), "macos_fork: true\n")
        configured_runner = described_class.new(dir)

        expect(configured_runner.send(:strategy_class)).to eq(Coatepec::Spec::GuardedForkStrategy)
      end
    end

    it "still uses SpawnStrategy on macOS when .coatepec.yml is absent" do
      stub_host_os("darwin24")

      expect(runner.send(:strategy_class)).to eq(Coatepec::Spec::SpawnStrategy)
    end
  end
end
