# frozen_string_literal: true

require "spec_helper"
require "coatepec/introspection/model"

# Coatepec::Introspection::Model#resolve! calls ::ActiveSupport::Inflector
# directly, relying on Rails already being booted by the time it's actually
# invoked in this gem's real architecture (see model.rb for the full
# rationale). The examples below deliberately call #resolve! without
# booting Rails, so this file -- and only this file -- needs to load that
# one piece of ActiveSupport itself to exercise that path in isolation.
require "active_support/inflector"

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

  describe "#build_association_data (private, unit-level)" do
    subject(:model) { described_class.new("Whatever") }

    let(:fake_reflection_class) do
      Class.new do
        def initialize(polymorphic:, klass_error: nil, foreign_key_error: nil)
          @polymorphic = polymorphic
          @klass_error = klass_error
          @foreign_key_error = foreign_key_error
        end

        def name = :target
        def macro = :belongs_to
        def through_reflection = nil
        def polymorphic? = @polymorphic

        def foreign_key
          raise @foreign_key_error if @foreign_key_error

          "target_id"
        end

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

    # A has_one/has_many :through reflection whose `through:` target is
    # itself a polymorphic belongs_to needs that target's class to resolve
    # its own foreign_key (ThroughReflection#foreign_key looks up the source
    # reflection via through_reflection.klass) -- and .klass on a polymorphic
    # reflection always raises ArgumentError. Rails signals the equivalent
    # "no fixed target class" case for an unresolvable class_name with
    # NameError, so both are covered here the same way association_class_name
    # already is above.
    it "returns nil foreign_key (rather than raising) when .foreign_key raises ArgumentError" do
      assoc = fake_reflection_class.new(
        polymorphic: false,
        foreign_key_error: ArgumentError.new("Polymorphic associations do not support computing the class.")
      )

      result = model.send(:build_association_data, assoc)

      expect(result[:foreign_key]).to be_nil
    end

    it "returns nil foreign_key (rather than raising) when .foreign_key raises NameError" do
      assoc = fake_reflection_class.new(polymorphic: false, foreign_key_error: NameError.new("Missing model class"))

      result = model.send(:build_association_data, assoc)

      expect(result[:foreign_key]).to be_nil
    end
  end

  describe "#safe_association_data safety net (private, unit-level)" do
    subject(:model) { described_class.new("Whatever") }

    let(:fake_reflection_class) do
      Class.new do
        def initialize(error: nil)
          @error = error
        end

        def name = :target
        def macro = :belongs_to
        def through_reflection = nil
        def polymorphic? = false
        def foreign_key = "target_id"

        def klass
          raise @error if @error

          Object
        end
      end
    end

    # association_class_name/association_foreign_key only rescue NameError
    # and ArgumentError -- the two failure modes seen in practice so far.
    # Anything else (the rest of ActiveRecord::ActiveRecordError's family,
    # covering whatever future reflection quirk turns up next) must not
    # crash the whole rails_model call for one bad association: it degrades
    # just that entry instead.
    it "returns a degraded entry instead of raising when .klass raises an unrescued ActiveRecord::ActiveRecordError" do
      # This unit spec never boots Rails (see the file header), so the real
      # activerecord gem isn't loaded here -- stub the one constant the
      # safety net's rescue clause names, the same way the ActiveRecord gate
      # example above stubs ActiveRecord::Base.
      stub_const("ActiveRecord::ActiveRecordError", Class.new(StandardError))
      assoc = fake_reflection_class.new(error: ActiveRecord::ActiveRecordError.new("something reflection-shaped broke"))

      result = model.send(:safe_association_data, assoc)

      expect(result).to include(name: "target", macro: "belongs_to", class_name: nil, foreign_key: nil, through: nil,
                                polymorphic: nil)
      expect(result[:error]).to include("ActiveRecordError", "something reflection-shaped broke")
    end

    it "still raises for an error outside the rescued family (a real Coatepec bug must not be silently swallowed)" do
      # Stubbed here too (even though it's expected not to match) so the
      # rescue clause's own constant lookup doesn't fail before TypeError
      # gets the chance to fall through unrescued -- see the note above.
      stub_const("ActiveRecord::ActiveRecordError", Class.new(StandardError))
      assoc = fake_reflection_class.new(error: TypeError.new("not the error this safety net is for"))

      expect { model.send(:safe_association_data, assoc) }.to raise_error(TypeError)
    end

    it "passes a healthy association through build_association_data unchanged" do
      assoc = fake_reflection_class.new

      expect(model.send(:safe_association_data, assoc)).to eq(model.send(:build_association_data, assoc))
    end
  end

  describe "#validators_for (private, unit-level)" do
    subject(:model) { described_class.new("Whatever") }

    # A Struct rather than an instance_double: `attributes`/`options` aren't
    # instance methods of a bare Class, so rspec-mocks would reject them.
    let(:validator_class) { stub_const("FakeValidator", Struct.new(:attributes, :options)) }

    def validator(attributes, options)
      validator_class.new(attributes, options)
    end

    it "collapses validators with an identical name, attributes and options into one entry" do
      klass = double(validators: [validator([:slug], { presence: true }), validator([:slug], { presence: true }),
                                  validator([:name], { presence: true })])

      entries = model.send(:validators_for, klass)

      expect(entries).to eq([
                              { name: "FakeValidator", attributes: ["slug"], options: { "presence" => true } },
                              { name: "FakeValidator", attributes: ["name"], options: { "presence" => true } }
                            ])
    end

    # SafeOptions strips Procs and Regexps, so two genuinely different declarations
    # sanitize to the same triple -- de-duplication has to key on the raw options.
    it "keeps validators whose options differ only in a Regexp or a Proc" do
      klass = double(validators: [validator([:email], { with: /@/ }), validator([:email], { with: /\.com\z/ }),
                                  validator([:name], { presence: true, if: -> { true } }),
                                  validator([:name], { presence: true, if: -> { false } })])

      entries = model.send(:validators_for, klass)

      expect(entries.size).to eq(4)
    end

    it "de-duplicates before applying the MAX_ITEMS cap" do
      klass = double(validators: Array.new(described_class::MAX_ITEMS + 1) { validator([:slug], {}) } +
                                 [validator([:name], {})])

      entries = model.send(:validators_for, klass)

      expect(entries.map { |v| v[:attributes] }).to eq([["slug"], ["name"]])
    end

    it "cuts an array option past MAX_OPTION_VALUES to its head and says so with count and truncated keys" do
      codes = ("AA".."ZZ").first(described_class::MAX_OPTION_VALUES + 30)
      klass = double(validators: [validator([:country_code], { in: codes, allow_nil: true })])

      options = model.send(:validators_for, klass).first[:options]

      expect(options.keys).to eq(%w[in in_count in_truncated allow_nil])
      expect(options["in"]).to eq(codes.first(described_class::MAX_OPTION_VALUES))
      expect(options["in_count"]).to eq(described_class::MAX_OPTION_VALUES + 30)
      expect(options["in_truncated"]).to be(true)
    end

    it "leaves an array option of MAX_OPTION_VALUES or fewer entries alone, with no sibling keys" do
      klass = double(validators: [validator([:status], { in: %i[draft published] }),
                                  validator([:code], { in: (1..described_class::MAX_OPTION_VALUES).to_a })])

      entries = model.send(:validators_for, klass)

      expect(entries.first[:options]).to eq("in" => %w[draft published])
      expect(entries.last[:options].keys).to eq(["in"])
    end
  end
end
