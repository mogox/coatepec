# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "securerandom"
require "tmpdir"

RSpec.describe Coatepec::Spec::Result do
  # A finished, zero-exit child: Process::Status cannot be built by hand, so run a real one.
  let(:status) { Process.wait2(Process.spawn("true")).last }
  let(:tmpdir) { Dir.mktmpdir("coatepec-result") }

  after { FileUtils.remove_entry(tmpdir) }

  def summary_file(examples, pending_count: 0)
    doc = {
      summary: { example_count: examples.size, failure_count: examples.count { |e| e[:status] == "failed" },
                 pending_count: pending_count, duration: 0.5 },
      examples: examples
    }
    path = File.join(tmpdir, "summary-#{SecureRandom.hex(4)}.json")
    File.write(path, JSON.generate(doc))
    path
  end

  def example(id, status, description: id, file: "./spec/x_spec.rb", line: 1)
    { id: id, full_description: description, status: status, file_path: file, line_number: line }
  end

  def build(examples, **opts)
    out_r, out_w = IO.pipe
    err_r, err_w = IO.pipe
    [out_w, err_w].each(&:close)
    described_class.build(pid: 1, status: status, out_r: out_r, err_r: err_r,
                          json_path: summary_file(examples, **opts.slice(:pending_count)),
                          **opts.slice(:include_passing, :include_stdout))
  ensure
    [out_r, err_r].compact.each(&:close)
  end

  def build_with_stdout(text, **opts)
    out_r = stdout_handle(text)
    err_r, err_w = IO.pipe
    err_w.close
    described_class.build(pid: 1, status: status, out_r: out_r, err_r: err_r, json_path: summary_file([]),
                          **opts.slice(:include_passing, :include_stdout))
  ensure
    [out_r, err_r].compact.each(&:close)
  end

  # A payload past MAX_OUTPUT_BYTES would fill a pipe's buffer before build reads it, so hand over a file handle.
  def stdout_handle(text)
    path = File.join(tmpdir, "stdout-#{SecureRandom.hex(4)}.txt")
    File.binwrite(path, text)
    File.open(path)
  end

  it "omits passing examples by default, keeping failed and pending ones" do
    result = build([example("a", "passed"), example("b", "failed"), example("c", "pending")])

    expect(result[:examples].map { |e| e[:id] }).to eq(%w[b c])
  end

  it "keeps every example when include_passing is true" do
    result = build([example("a", "passed"), example("b", "failed")], include_passing: true)

    expect(result[:examples].map { |e| e[:id] }).to eq(%w[a b])
  end

  it "applies the 500 cap after dropping passing examples" do
    examples = (1..600).map { |i| example("p#{i}", "passed") } + [example("f", "failed")]

    result = build(examples)

    expect(result[:examples].map { |e| e[:id] }).to eq(["f"])
  end

  it "applies the 500 cap to the kept examples when include_passing is true" do
    examples = (1..600).map { |i| example("p#{i}", "passed") }

    result = build(examples, include_passing: true)

    expect(result[:examples].size).to eq(500)
  end

  it "omits description when it equals id and keeps it when it differs" do
    result = build([example("same", "failed"), example("./x[1:1]", "failed", description: "x does y")])

    expect(result[:examples].first).not_to have_key(:description)
    expect(result[:examples].last[:description]).to eq("x does y")
  end

  it "reports pending_count in the summary" do
    result = build([example("c", "pending")], pending_count: 1)

    expect(result[:summary]).to include(example_count: 1, failure_count: 0, pending_count: 1)
  end

  it "collapses repeated failure blocks in stdout" do
    block = "Error:\nT#test_%s:\nRuntimeError: boom\n    test/t_test.rb:%d:in 'x'\n\n" \
            "bin/rails test test/t_test.rb:%d\n\n"
    text = "# Running:\n\nEE\n\n#{format(block, "a", 3, 2)}#{format(block, "b", 7, 6)}2 runs, 2 errors\n"

    result = build_with_stdout(text, include_stdout: "always")

    expect(result[:stdout].scan("RuntimeError: boom").size).to eq(1)
    expect(result[:stdout]).to include("1 more test failed with this same error: T#test_b\n")
    expect(result[:stdout_truncated]).to be(false)
  end

  it "drops captured stdout text when include_stdout is never but still reports truncation" do
    result = build_with_stdout("x" * (described_class::MAX_OUTPUT_BYTES + 1), include_stdout: "never")

    expect(result[:stdout]).to be_nil
    expect(result[:stdout_truncated]).to be(true)
  end

  it "nulls stdout but keeps the key when include_stdout is never" do
    result = build([example("b", "failed")], include_stdout: "never")

    expect(result).to have_key(:stdout)
    expect(result[:stdout]).to be_nil
    expect(result[:stderr]).to eq("")
    expect(result.keys.index(:stdout)).to eq(result.keys.index(:stdout_truncated) - 1)
  end

  it "drops stdout on a passing run by default and keeps it on a failing one" do
    passed = build_with_stdout("1 example, 0 failures\n")
    failed_status = Process.wait2(Process.spawn("false")).last
    out_r, out_w = IO.pipe
    err_r, err_w = IO.pipe
    out_w.write("1 example, 1 failure\n")
    [out_w, err_w].each(&:close)
    failed = described_class.build(pid: 1, status: failed_status, out_r: out_r, err_r: err_r,
                                   json_path: summary_file([example("b", "failed")]))

    expect(passed[:stdout]).to be_nil
    expect(failed[:stdout]).to eq("1 example, 1 failure\n")
  ensure
    [out_r, err_r].compact.each(&:close)
  end

  it "keeps stdout on a passing run when include_stdout is always" do
    result = build_with_stdout("1 example, 0 failures\n", include_stdout: "always")

    expect(result[:stdout]).to eq("1 example, 0 failures\n")
  end

  it "rejects an unknown include_stdout mode" do
    expect { build([], include_stdout: "sometimes") }
      .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:invalid_include_stdout) }
  end

  it "omits the process fields when the child exited normally" do
    result = build([example("b", "failed")])

    expect(result.keys).to eq(%i[status exit_code stdout stdout_truncated stderr stderr_truncated summary examples])
  end

  # A child killed by a signal (a timeout's TERM/KILL, a crash) has no exit code; the signal fields say what happened.
  it "reports the process fields after exit_code when the child was signaled" do
    signaled = Process.wait2(Process.spawn("sh", "-c", "kill -KILL $$")).last
    out_r, out_w = IO.pipe
    err_r, err_w = IO.pipe
    [out_w, err_w].each(&:close)
    result = described_class.build(pid: 42, status: signaled, out_r: out_r, err_r: err_r, json_path: summary_file([]))

    expect(result[:status]).to eq("failed")
    expect(result.keys.first(7)).to eq(%i[status exit_code child_pid signaled termsig stopsig coredump])
    expect(result).to include(child_pid: 42, signaled: true, termsig: Signal.list["KILL"], exit_code: nil)
  ensure
    [out_r, err_r].compact.each(&:close)
  end
end
