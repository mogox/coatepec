# frozen_string_literal: true

require "spec_helper"
require "coatepec/introspection/job"

# Coatepec::Introspection::Job#resolve! calls ::ActiveSupport::Inflector
# directly, relying on Rails already being booted by the time it's actually
# invoked in this gem's real architecture (see job.rb and the identical
# rationale in model_spec.rb). These examples deliberately call #resolve!
# without booting Rails, so this file needs that one piece of ActiveSupport
# itself to exercise that path in isolation.
require "active_support/inflector"

RSpec.describe Coatepec::Introspection::Job do
  describe "name validation" do
    it "raises invalid_job_name for a lowercase-starting name" do
      expect { described_class.new("sendMailJob").call }
        .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:invalid_job_name) }
    end

    it "raises invalid_job_name for a name containing invalid characters" do
      expect { described_class.new("SendMailJob; puts 1").call }
        .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:invalid_job_name) }
    end

    it "accepts a well-formed namespaced constant name without raising invalid_job_name" do
      # Resolution will fail with job_not_found (no Rails app is booted in
      # this unit test), but that's a different error than invalid_job_name --
      # this confirms the regex itself accepts namespaced paths.
      expect { described_class.new("Admin::SendMailJob").call }
        .to raise_error(Coatepec::Error) { |e| expect(e.code).not_to eq(:invalid_job_name) }
    end

    it "raises invalid_job_name for non-String input" do
      [nil, 123].each do |bad_name|
        expect { described_class.new(bad_name).call }
          .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:invalid_job_name) }
      end
    end

    it "raises invalid_job_name for an empty string" do
      expect { described_class.new("").call }
        .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:invalid_job_name) }
    end

    it "raises invalid_job_name for a name with a leading ::" do
      expect { described_class.new("::SendMailJob").call }
        .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:invalid_job_name) }
    end
  end

  describe "ActiveJob gate (isolated, no Rails boot)" do
    it "raises not_active_job for a resolved class that isn't < ActiveJob::Base" do
      stub_const("ActiveJob::Base", Class.new)
      plain_class = Class.new
      stub_const("PlainClass", plain_class)
      allow(::ActiveSupport::Inflector).to receive(:safe_constantize).with("PlainClass").and_return(plain_class)

      expect { described_class.new("PlainClass").call }
        .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:not_active_job) }
    end

    it "raises job_not_found for a well-formed but unresolvable constant" do
      allow(::ActiveSupport::Inflector).to receive(:safe_constantize).with("NoSuchJob").and_return(nil)

      expect { described_class.new("NoSuchJob").call }
        .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:job_not_found) }
    end
  end

  describe "#build_metadata (private, unit-level)" do
    subject(:introspector) { described_class.new("Whatever") }

    # A minimal stand-in for an ActiveJob class: just enough surface for
    # build_metadata to read, without requiring the real activejob gem in
    # this Rails-boot-free unit spec (mirrors model_spec.rb's fake_reflection_class
    # approach for the same reason).
    let(:fake_job_class) do
      Class.new do
        def self.name = "FakeJob"
        def self.priority = 5
        def self.rescue_handlers = [["ArgumentError", proc {}], ["TypeError", proc {}], ["ArgumentError", proc {}]]

        callback_struct = Struct.new(:kind, :filter) # rubocop:disable Lint/StructNewOverride
        define_singleton_method(:_perform_callbacks) do
          [callback_struct.new(:before, :log_start), callback_struct.new(:around, proc { |_job, block| block.call })]
        end

        def initialize; end

        def queue_name = "low_priority"
      end
    end

    it "builds the full metadata hash from class + instance ActiveJob APIs" do
      result = introspector.send(:build_metadata, fake_job_class)

      expect(result).to eq(
        name: "FakeJob",
        queue_name: "low_priority",
        queue_priority: 5,
        callbacks: [{ kind: "before", filter: "log_start" }, { kind: "around", filter: "(block)" }],
        rescued_exceptions: %w[ArgumentError TypeError]
      )
    end

    it "deduplicates rescued_exceptions" do
      # already covered by the ArgumentError appearing twice in fake_job_class
      # above -- asserted explicitly here so the intent isn't lost if the
      # fixture above changes.
      result = introspector.send(:build_metadata, fake_job_class)

      expect(result[:rescued_exceptions].count("ArgumentError")).to eq(1)
    end

    it "reports a Symbol filter as its bare method name" do
      result = introspector.send(:build_metadata, fake_job_class)

      before_callback = result[:callbacks].find { |c| c[:kind] == "before" }
      expect(before_callback[:filter]).to eq("log_start")
    end

    it "reports a Proc filter as the literal string \"(block)\", never its source location" do
      result = introspector.send(:build_metadata, fake_job_class)

      around_callback = result[:callbacks].find { |c| c[:kind] == "around" }
      expect(around_callback[:filter]).to eq("(block)")
    end
  end
end
