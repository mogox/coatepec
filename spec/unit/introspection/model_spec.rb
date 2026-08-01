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

    it "raises invalid_model_name for non-String input" do
      [nil, 123].each do |bad_name|
        expect { described_class.new(bad_name).call }
          .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:invalid_model_name) }
      end
    end

    it "raises invalid_model_name for an empty string" do
      expect { described_class.new("").call }
        .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:invalid_model_name) }
    end

    it "raises invalid_model_name for a name with a trailing newline" do
      expect { described_class.new("Widget\n").call }
        .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:invalid_model_name) }
    end

    it "raises invalid_model_name for a name with a leading ::" do
      expect { described_class.new("::Widget").call }
        .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:invalid_model_name) }
    end

    it "raises invalid_model_name for a name with a trailing ::" do
      expect { described_class.new("Widget::").call }
        .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:invalid_model_name) }
    end
  end

  describe "ActiveRecord gate (isolated, no Rails boot)" do
    it "raises not_active_record_model for a resolved class that isn't < ActiveRecord::Base" do
      stub_const("ActiveRecord::Base", Class.new)
      plain_class = Class.new
      stub_const("PlainClass", plain_class)
      allow(::ActiveSupport::Inflector).to receive(:safe_constantize).with("PlainClass").and_return(plain_class)

      expect { described_class.new("PlainClass").call }
        .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:not_active_record_model) }
    end
  end

  describe "#safe_option_value (private, unit-level)" do
    subject(:model) { described_class.new("Whatever") }

    it "keeps primitive values" do
      expect(model.send(:safe_option_value, 5)).to eq(5)
      expect(model.send(:safe_option_value, "text")).to eq("text")
      expect(model.send(:safe_option_value, true)).to eq(true)
      expect(model.send(:safe_option_value, false)).to eq(false)
      expect(model.send(:safe_option_value, nil)).to be_nil
      expect(model.send(:safe_option_value, [1, "two", 3])).to eq([1, "two", 3])
    end

    it "converts Symbols to Strings" do
      expect(model.send(:safe_option_value, :on_create)).to eq("on_create")
    end

    it "drops a Proc value (e.g. an `if:`/`unless:` option) rather than serializing it" do
      # Proc#to_s includes the absolute source file path and line number of
      # wherever the Proc was defined -- for a validator's `if:`/`unless:`
      # option, that's the *host app's* source, so it must never surface.
      expect(model.send(:safe_option_value, -> { true })).to be_nil
    end

    it "drops a Regexp value (e.g. a `with:` option)" do
      expect(model.send(:safe_option_value, /abc/)).to be_nil
    end

    it "drops an Array containing non-primitive elements" do
      expect(model.send(:safe_option_value, [1, -> { true }])).to be_nil
    end
  end

  describe "#build_association_data (private, unit-level)" do
    subject(:model) { described_class.new("Whatever") }

    let(:fake_reflection_class) do
      Class.new do
        def initialize(polymorphic:, klass_error: nil)
          @polymorphic = polymorphic
          @klass_error = klass_error
        end

        def name = :target
        def macro = :belongs_to
        def foreign_key = "target_id"
        def through_reflection = nil
        def polymorphic? = @polymorphic

        def klass
          raise @klass_error if @klass_error

          "should not be reached for a polymorphic reflection"
        end
      end
    end

    it "returns nil class_name for a polymorphic association without calling .klass" do
      assoc = fake_reflection_class.new(polymorphic: true)

      result = model.send(:build_association_data, assoc)

      expect(result[:polymorphic]).to eq(true)
      expect(result[:class_name]).to be_nil
    end

    it "returns nil class_name (rather than raising) when .klass raises NameError" do
      assoc = fake_reflection_class.new(polymorphic: false, klass_error: NameError.new("Missing model class"))

      result = model.send(:build_association_data, assoc)

      expect(result[:class_name]).to be_nil
    end

    it "returns nil class_name (rather than raising) when .klass raises ArgumentError" do
      assoc = fake_reflection_class.new(polymorphic: false, klass_error: ArgumentError.new("cannot classify"))

      result = model.send(:build_association_data, assoc)

      expect(result[:class_name]).to be_nil
    end
  end
end
