# frozen_string_literal: true

require "spec_helper"

RSpec.describe Coatepec::Spec::FlakyChecker, type: :integration do
  def run_in_worker(ruby_tail)
    lib_path = File.expand_path("../../../lib", __dir__)
    script = <<~RUBY
      $LOAD_PATH.unshift(#{lib_path.inspect})
      require "coatepec"
      require "rspec/core"
      runtime = Coatepec::Worker::RailsRuntime.new(#{FIXTURE_APP_ROOT.inspect})
      runtime.boot!
      #{ruby_tail}
    RUBY
    run_in_fixture_app(script)
  end

  # 10 rounds against a genuinely 50/50 order-dependent example gives a
  # false-negative probability (every round happening to land the same
  # way) under 0.2% -- low enough to trust, not zero. If this ever flakes
  # in CI, that's this test's own known tradeoff, not a regression to chase.
  it "detects the fixture's genuinely order-dependent example as flaky" do
    stdout, stderr, status = run_in_worker(<<~RUBY)
      checker = Coatepec::Spec::FlakyChecker.new(#{FIXTURE_APP_ROOT.inspect}, rails_runtime: runtime)
      result = checker.call(paths: ["spec/flaky_fixture_spec.rb"], runs: 10)
      puts JSON.generate(result)
    RUBY

    expect(status).to be_success, stderr
    result = JSON.parse(stdout.lines.last)

    expect(result["runs"]).to eq(10)
    expect(result["rounds"].map { |r| r["seed"] }.uniq.size).to be > 1
    # "description" is RSpec's full_description (see Result#example_fields), which
    # includes the enclosing describe block's text, not just the example's own
    # "it" string -- hence include? rather than an exact match against the bare
    # "it" description from the fixture source.
    flaky = result["flaky_examples"].find { |e| e["description"].include?("depends on shared state") }
    expect(flaky).not_to be_nil, "expected \"depends on shared state\" to show up as flaky across 10 rounds -- " \
                                  "got: #{result["flaky_examples"].inspect}"
    expect(flaky["failure_count"]).to be > 0
    expect(flaky["pass_count"]).to be > 0
    always_passes = result["flaky_examples"].find { |e| e["description"].include?("primes the shared state") }
    expect(always_passes).to be_nil
  end

  it "reports empty flaky_examples/consistently_failing for a consistently-passing spec" do
    stdout, stderr, status = run_in_worker(<<~RUBY)
      checker = Coatepec::Spec::FlakyChecker.new(#{FIXTURE_APP_ROOT.inspect}, rails_runtime: runtime)
      result = checker.call(paths: ["spec/passing_spec.rb"], runs: 3)
      puts JSON.generate(result)
    RUBY

    expect(status).to be_success, stderr
    result = JSON.parse(stdout.lines.last)

    expect(result["flaky_examples"]).to eq([])
    expect(result["consistently_failing"]).to eq([])
  end

  it "reports a spec that always fails as consistently_failing, not flaky" do
    stdout, stderr, status = run_in_worker(<<~RUBY)
      checker = Coatepec::Spec::FlakyChecker.new(#{FIXTURE_APP_ROOT.inspect}, rails_runtime: runtime)
      result = checker.call(paths: ["spec/failing_spec.rb"], runs: 3)
      puts JSON.generate(result)
    RUBY

    expect(status).to be_success, stderr
    result = JSON.parse(stdout.lines.last)

    expect(result["flaky_examples"]).to eq([])
    expect(result["consistently_failing"].size).to eq(1)
  end
end
