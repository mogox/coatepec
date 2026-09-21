# frozen_string_literal: true

require "spec_helper"

RSpec.describe Coatepec::Worker::RailsRuntime do
  describe "#record_execution_mode" do
    it "starts the counter at zero" do
      expect(described_class.new(Dir.pwd).fallback_count).to eq(0)
    end

    it "counts only the modes that fell back to spawn" do
      runtime = described_class.new(Dir.pwd)

      %w[fork spawn spawn_fallback fork spawn_after_crash].each { |mode| runtime.record_execution_mode(mode) }

      expect(runtime.fallback_count).to eq(2)
    end
  end
end
