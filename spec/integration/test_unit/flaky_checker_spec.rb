# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Coatepec::Spec::FlakyChecker with Minitest selectors", type: :integration do
  def run_in_worker(ruby_tail)
    lib_path = File.expand_path("../../../lib", __dir__)
    script = <<~RUBY
      $LOAD_PATH.unshift(#{lib_path.inspect})
      require "coatepec"
      runtime = Coatepec::Worker::RailsRuntime.new(#{FIXTURE_APP_ROOT.inspect})
      runtime.boot!
      #{ruby_tail}
    RUBY
    run_in_fixture_app(script)
  end

  # Same probability argument as the RSpec version: 10 rounds of a 50/50
  # order-dependent pair leaves a <0.2% chance of every round agreeing.
  it "detects the fixture's order-dependent Minitest test as flaky" do
    stdout, stderr, status = run_in_worker(<<~RUBY)
      checker = Coatepec::Spec::FlakyChecker.new(#{FIXTURE_APP_ROOT.inspect}, rails_runtime: runtime)
      puts JSON.generate(checker.call(paths: ["test/models/order_dependent_test.rb"], runs: 10))
    RUBY

    expect(status).to be_success, stderr
    result = JSON.parse(stdout.lines.last)

    expect(result["runs"]).to eq(10)
    expect(result["rounds"].map { |r| r["seed"] }.uniq.size).to be > 1
    flaky = result["flaky_examples"].find { |e| e["id"] == "OrderDependentTest#test_depends_on_shared_state" }
    expect(flaky).not_to be_nil, "expected the order-dependent test to be flaky -- got #{result["flaky_examples"]}"
    expect(flaky["pass_count"]).to be > 0
    expect(flaky["failure_count"]).to be > 0
    expect(result["flaky_examples"].map { |e| e["id"] })
      .not_to include("OrderDependentTest#test_primes_the_shared_state")
  end

  it "reports a consistently failing Minitest test under consistently_failing" do
    stdout, stderr, status = run_in_worker(<<~RUBY)
      checker = Coatepec::Spec::FlakyChecker.new(#{FIXTURE_APP_ROOT.inspect}, rails_runtime: runtime)
      puts JSON.generate(checker.call(paths: ["test/models/failing_test.rb"], runs: 3))
    RUBY

    expect(status).to be_success, stderr
    result = JSON.parse(stdout.lines.last)

    expect(result["flaky_examples"]).to eq([])
    expect(result["consistently_failing"].map { |e| e["id"] })
      .to contain_exactly("FailingTest#test_fails_an_assertion", "FailingTest#test_raises")
  end
end
