# frozen_string_literal: true

require "spec_helper"
require "coatepec/test_unit/line_filtering"

RSpec.describe Coatepec::TestUnit::LineFiltering do
  describe ".module_for" do
    it "targets run_suite/:include on Minitest 6" do
      expect(described_class.module_for("6.0.6").instance_methods).to eq([:run_suite])
    end

    it "targets run/:filter on Minitest 5" do
      expect(described_class.module_for("5.25.1").instance_methods).to eq([:run])
    end
  end

  describe "composition" do
    let(:runner) { class_double("Rails::TestUnit::Runner") }

    before { stub_const("Rails::TestUnit::Runner", runner) }

    it "composes the Minitest 6 :include option through Rails' compose_filter and calls super" do
      composed = Object.new
      allow(runner).to receive(:compose_filter).with(anything, "/x/").and_return(composed)
      # The method being overridden must live on a *parent's* singleton, as
      # Runnable.run_suite does relative to ActiveSupport::TestCase: a
      # method defined directly on the extended class's own singleton would
      # shadow the extended module and never reach it.
      parent = Class.new do
        def self.run_suite(_reporter, options = {})
          options
        end
      end
      base = Class.new(parent)
      base.extend(described_class.module_for("6.0.6"))

      expect(base.run_suite(:reporter, include: "/x/")).to eq(include: composed)
    end

    it "composes the Minitest 5 :filter option the same way" do
      composed = Object.new
      allow(runner).to receive(:compose_filter).with(anything, nil).and_return(composed)
      parent = Class.new do
        def self.run(_reporter, options = {})
          options
        end
      end
      base = Class.new(parent)
      base.extend(described_class.module_for("5.25.1"))

      expect(base.run(:reporter)).to eq(filter: composed)
    end
  end
end
