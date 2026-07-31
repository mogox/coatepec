# frozen_string_literal: true

require "spec_helper"
require "coatepec/cli"

RSpec.describe Coatepec::CLI do
  describe ".parse" do
    it "parses --root" do
      expect(described_class.parse(["--root", "/app"])).to eq(root: "/app", debug: false)
    end

    it "parses --debug" do
      expect(described_class.parse(["--root", "/app", "--debug"])).to eq(root: "/app", debug: true)
    end

    it "defaults root to nil" do
      expect(described_class.parse([])).to eq(root: nil, debug: false)
    end
  end
end
