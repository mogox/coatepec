# frozen_string_literal: true

require "spec_helper"
require "coatepec/cli"

RSpec.describe Coatepec::CLI do
  describe ".parse" do
    it "parses --root" do
      expect(described_class.parse(["--root", "/app"])).to eq(root: "/app", debug: false)
    end

    it "parses --debug and exports COATEPEC_DEBUG for downstream diagnostics" do
      original = ENV.fetch("COATEPEC_DEBUG", nil)
      ENV.delete("COATEPEC_DEBUG")

      begin
        expect(described_class.parse(["--root", "/app", "--debug"])).to eq(root: "/app", debug: true)
        expect(ENV.fetch("COATEPEC_DEBUG", nil)).to eq("1")
      ensure
        original.nil? ? ENV.delete("COATEPEC_DEBUG") : ENV["COATEPEC_DEBUG"] = original
      end
    end

    it "leaves COATEPEC_DEBUG unset without --debug" do
      original = ENV.fetch("COATEPEC_DEBUG", nil)
      ENV.delete("COATEPEC_DEBUG")

      begin
        described_class.parse(["--root", "/app"])
        expect(ENV.fetch("COATEPEC_DEBUG", nil)).to be_nil
      ensure
        original.nil? ? ENV.delete("COATEPEC_DEBUG") : ENV["COATEPEC_DEBUG"] = original
      end
    end

    it "defaults root to nil" do
      expect(described_class.parse([])).to eq(root: nil, debug: false)
    end
  end
end
