# frozen_string_literal: true

require "spec_helper"
require "coatepec/introspection/safe_options"

RSpec.describe Coatepec::Introspection::SafeOptions do
  describe ".value_for" do
    it "keeps primitive values" do
      expect(described_class.value_for(5)).to eq(5)
      expect(described_class.value_for("text")).to eq("text")
      expect(described_class.value_for(true)).to eq(true)
      expect(described_class.value_for(false)).to eq(false)
      expect(described_class.value_for(nil)).to be_nil
      expect(described_class.value_for([1, "two", 3])).to eq([1, "two", 3])
    end

    it "converts Symbols to Strings" do
      expect(described_class.value_for(:on_create)).to eq("on_create")
    end

    it "drops a Proc value (e.g. an `if:`/`unless:` option) rather than serializing it" do
      # Proc#to_s includes the absolute source file path and line number of
      # wherever the Proc was defined -- for a validator's `if:`/`unless:`
      # option, that's the *host app's* source, so it must never surface.
      expect(described_class.value_for(-> { true })).to be_nil
    end

    it "drops a Regexp value (e.g. a `with:` option)" do
      expect(described_class.value_for(/abc/)).to be_nil
    end

    it "drops an Array containing non-primitive elements" do
      expect(described_class.value_for([1, -> { true }])).to be_nil
    end

    it "stringifies Symbol elements inside an Array (e.g. `inclusion: { in: %i[...] }`)" do
      expect(described_class.value_for(%i[draft published])).to eq(%w[draft published])
      expect(described_class.value_for([:draft, "published", 3])).to eq(["draft", "published", 3])
    end
  end

  describe ".call" do
    it "filters a whole options hash down to its primitive entries" do
      result = described_class.call(minimum: 2, if: -> { true }, in: %i[draft published])

      expect(result).to eq("minimum" => 2, "in" => %w[draft published])
    end

    it "keeps a key whose value is a genuine nil" do
      expect(described_class.call(allow_nil: nil)).to eq("allow_nil" => nil)
    end
  end
end
