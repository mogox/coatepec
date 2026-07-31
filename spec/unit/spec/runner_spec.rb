# frozen_string_literal: true

require "spec_helper"

RSpec.describe Coatepec::Spec::Runner do
  subject(:runner) { described_class.new(FIXTURE_APP_ROOT) }

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
  end
end
