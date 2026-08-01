# frozen_string_literal: true

require "spec_helper"
require "coatepec/introspection/model"

RSpec.describe Coatepec::Introspection::Model do
  describe "name validation" do
    it "raises invalid_model_name for a lowercase-starting name" do
      expect { described_class.new("widget").call }
        .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:invalid_model_name) }
    end

    it "raises invalid_model_name for a name containing invalid characters" do
      expect { described_class.new("Widget; puts 1").call }
        .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:invalid_model_name) }
    end

    it "accepts a well-formed namespaced constant name without raising invalid_model_name" do
      # Resolution will fail with model_not_found (no Rails app is booted in
      # this unit test), but that's a different error than invalid_model_name --
      # this confirms the regex itself accepts namespaced paths.
      expect { described_class.new("Admin::Widget").call }
        .to raise_error(Coatepec::Error) { |e| expect(e.code).not_to eq(:invalid_model_name) }
    end
  end
end
