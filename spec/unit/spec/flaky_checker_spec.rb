# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Coatepec::Spec::FlakyChecker do
  subject(:checker) { described_class.new(project_root, rails_runtime: rails_runtime) }

  let(:project_root) do
    Dir.mktmpdir.tap { |dir| File.write(File.join(dir, "Gemfile"), "source \"https://rubygems.org\"\n") }
  end
  let(:rails_runtime) { instance_double(Coatepec::Worker::RailsRuntime) }

  after { FileUtils.remove_entry(project_root) }

  describe "#call budget validation" do
    it "raises flaky_check_budget_exceeded when timeout_seconds * runs exceeds the combined budget" do
      expect { checker.call(paths: ["spec/x_spec.rb"], timeout_seconds: 900, runs: 3) }
        .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:flaky_check_budget_exceeded) }
    end

    it "does not raise when timeout_seconds * runs is exactly at the combined budget" do
      runner_double = instance_double(Coatepec::Spec::Runner)
      allow(Coatepec::Spec::Runner).to receive(:new).and_return(runner_double)
      allow(runner_double).to receive(:run).and_return(status: "passed", examples: [])

      expect { checker.call(paths: ["spec/x_spec.rb"], timeout_seconds: 900, runs: 2) }.not_to raise_error
    end
  end

  describe "#group_examples_by_id / #classify (private, unit-level)" do
    def example_fields(id:, status:, description: "desc", file_path: "spec/x_spec.rb", line_number: 1)
      { id: id, description: description, status: status, file_path: file_path, line_number: line_number }
    end

    it "classifies an example with mixed statuses across rounds as flaky" do
      rounds = [
        { seed: 1, status: "failed", examples: [example_fields(id: "./x[1:1]", status: "passed")] },
        { seed: 2, status: "failed", examples: [example_fields(id: "./x[1:1]", status: "failed")] },
        { seed: 3, status: "passed", examples: [example_fields(id: "./x[1:1]", status: "passed")] }
      ]

      by_id = checker.send(:group_examples_by_id, rounds)
      flaky = checker.send(:classify, by_id) { |statuses| statuses.uniq.size > 1 }

      expect(flaky.size).to eq(1)
      expect(flaky.first[:id]).to eq("./x[1:1]")
      expect(flaky.first[:statuses]).to eq(%w[passed failed passed])
      expect(flaky.first[:pass_count]).to eq(2)
      expect(flaky.first[:failure_count]).to eq(1)
    end

    it "classifies an example that fails every round it appears in as consistently_failing, not flaky" do
      rounds = [
        { seed: 1, status: "failed", examples: [example_fields(id: "./x[1:1]", status: "failed")] },
        { seed: 2, status: "failed", examples: [example_fields(id: "./x[1:1]", status: "failed")] }
      ]

      by_id = checker.send(:group_examples_by_id, rounds)
      flaky = checker.send(:classify, by_id) { |statuses| statuses.uniq.size > 1 }
      failing = checker.send(:classify, by_id) { |statuses| statuses.uniq == ["failed"] }

      expect(flaky).to be_empty
      expect(failing.size).to eq(1)
      expect(failing.first[:id]).to eq("./x[1:1]")
    end

    it "omits an example that passes every round from both classifications" do
      rounds = [
        { seed: 1, status: "passed", examples: [example_fields(id: "./x[1:1]", status: "passed")] },
        { seed: 2, status: "passed", examples: [example_fields(id: "./x[1:1]", status: "passed")] }
      ]

      by_id = checker.send(:group_examples_by_id, rounds)
      flaky = checker.send(:classify, by_id) { |statuses| statuses.uniq.size > 1 }
      failing = checker.send(:classify, by_id) { |statuses| statuses.uniq == ["failed"] }

      expect(flaky).to be_empty
      expect(failing).to be_empty
    end

    it "does not count a round with no examples data (a crashed round) as evidence against an example" do
      rounds = [
        { seed: 1, status: "passed", examples: [example_fields(id: "./x[1:1]", status: "passed")] },
        { seed: 2, status: "failed", examples: [] }, # simulates a crashed/timed-out round
        { seed: 3, status: "passed", examples: [example_fields(id: "./x[1:1]", status: "passed")] }
      ]

      by_id = checker.send(:group_examples_by_id, rounds)
      failing = checker.send(:classify, by_id) { |statuses| statuses.uniq == ["failed"] }

      expect(failing).to be_empty
      expect(by_id["./x[1:1]"][:statuses]).to eq(%w[passed passed])
    end

    it "truncates classified results to MAX_ITEMS" do
      examples_count = described_class::MAX_ITEMS + 5
      rounds = [
        {
          seed: 1, status: "failed",
          examples: (1..examples_count).map { |i| example_fields(id: "./x[#{i}]", status: "passed") }
        },
        {
          seed: 2, status: "failed",
          examples: (1..examples_count).map { |i| example_fields(id: "./x[#{i}]", status: "failed") }
        }
      ]

      by_id = checker.send(:group_examples_by_id, rounds)
      flaky = checker.send(:classify, by_id) { |statuses| statuses.uniq.size > 1 }

      expect(flaky.size).to eq(described_class::MAX_ITEMS)
    end
  end
end
