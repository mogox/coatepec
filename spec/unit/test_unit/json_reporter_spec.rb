# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "json"
require "minitest"
require "coatepec/test_unit/json_reporter"

RSpec.describe Coatepec::TestUnit::JsonReporter do
  let(:root) { Dir.mktmpdir }
  let(:json_path) { File.join(root, "out.json") }
  let(:test_file) { File.join(root, "test/models/widget_test.rb") }

  after { FileUtils.rm_rf(root) }

  def result(name, line, failure = nil)
    r = ::Minitest::Result.new(name)
    r.klass = "WidgetTest"
    r.source_location = [test_file, line]
    r.time = 0.25
    r.assertions = 1
    r.failures = [failure].compact
    r
  end

  def run_reporter(*results)
    reporter = described_class.new(json_path, root)
    reporter.start
    results.each { |r| reporter.record(r) }
    reporter.report
    JSON.parse(File.read(json_path))
  end

  it "writes examples in the shape Spec::Result reads, with project-relative ./ paths" do
    doc = run_reporter(result("test_is_valid", 7))

    expect(doc["examples"]).to eq([{
                                    "id" => "WidgetTest#test_is_valid",
                                    "full_description" => "WidgetTest#test_is_valid",
                                    "status" => "passed",
                                    "file_path" => "./test/models/widget_test.rb",
                                    "line_number" => 7
                                  }])
    expect(doc.to_json).not_to include(root)
  end

  it "maps an assertion failure and an unexpected error to failed, and a skip to pending" do
    doc = run_reporter(
      result("test_fails", 3, ::Minitest::Assertion.new("nope")),
      result("test_errors", 5, ::Minitest::UnexpectedError.new(RuntimeError.new("boom"))),
      result("test_skips", 9, ::Minitest::Skip.new("later"))
    )

    expect(doc["examples"].map { |e| e["status"] }).to eq(%w[failed failed pending])
    expect(doc["summary"]["pending_count"]).to eq(1)
  end

  it "counts failed tests, not failure objects, and reports wall-clock duration" do
    doc = run_reporter(result("test_a", 1), result("test_b", 2, ::Minitest::Assertion.new("x")))

    expect(doc["summary"]["example_count"]).to eq(2)
    expect(doc["summary"]["failure_count"]).to eq(1)
    expect(doc["summary"]["pending_count"]).to eq(0)
    expect(doc["summary"]["duration"]).to be_a(Float)
  end

  it "never changes the run's pass/fail verdict" do
    expect(described_class.new(json_path, root).passed?).to be(true)
  end

  it "leaves no partial document if writing is interrupted" do
    reporter = described_class.new(json_path, root)
    reporter.start
    reporter.record(result("test_a", 1))
    allow(File).to receive(:rename).and_raise(Errno::EIO)

    expect { reporter.report }.to raise_error(Errno::EIO)
    expect(File.exist?(json_path)).to be(false)
    expect(File.exist?("#{json_path}.tmp")).to be(false)
  end

  it "is a Spec::Result-compatible document end to end" do
    run_reporter(result("test_a", 1))
    summary = Coatepec::Spec::Result.read_summary(json_path)

    expect(Coatepec::Spec::Result.summary_fields(summary))
      .to include(example_count: 1, failure_count: 0, pending_count: 0)
    expect(Coatepec::Spec::Result.example_fields(summary["examples"].first))
      .to eq(id: "WidgetTest#test_a", status: "passed",
             file_path: "./test/models/widget_test.rb", line_number: 1)
  end
end
