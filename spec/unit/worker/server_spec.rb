# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Coatepec::Worker::Server do
  describe "#handle_status (private)" do
    def server_with(strategy_name)
      runtime = instance_double(Coatepec::Worker::RailsRuntime, status: { lifecycle_state: "ready" },
                                                                fallback_count: 3)
      allow(Coatepec::Worker::RailsRuntime).to receive(:new).and_return(runtime)
      runner = instance_double(Coatepec::Spec::Runner, strategy_name: strategy_name)
      allow(Coatepec::Spec::Runner).to receive(:new).and_return(runner)
      described_class.new(FIXTURE_APP_ROOT, input: StringIO.new, protocol_output: StringIO.new)
    end

    it "reports the fallback count under the guarded fork" do
      expect(server_with("guarded_fork").send(:handle_status))
        .to eq(lifecycle_state: "ready", spec_strategy: "guarded_fork", fallbacks: 3)
    end

    it "reports fallbacks as nil under any other strategy" do
      expect(server_with("fork").send(:handle_status))
        .to eq(lifecycle_state: "ready", spec_strategy: "fork", fallbacks: nil)
    end
  end
end
