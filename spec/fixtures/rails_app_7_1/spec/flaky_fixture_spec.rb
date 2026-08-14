# frozen_string_literal: true

# Deliberately order-dependent: "depends on shared state" passes when
# "primes the shared state" happens to run first under a given --seed, and
# fails when it runs first instead. Exists solely so FlakyChecker's
# integration test (spec/integration/spec/flaky_checker_spec.rb) has a
# genuine, reproducible-by-repetition flaky example to detect -- this is
# not a demonstration of good spec hygiene, and this file is meant to be
# targeted directly by path (as the integration tests do), not swept
# incidentally by a bare `bundle exec rspec` run of this whole fixture
# app -- same precedent as the pre-existing intentionally-failing
# spec/failing_spec.rb in this same directory.
RSpec.describe "order dependent fixture" do
  before(:all) { $coatepec_flaky_fixture_state = nil }

  it "primes the shared state" do
    $coatepec_flaky_fixture_state = :primed

    expect($coatepec_flaky_fixture_state).to eq(:primed)
  end

  it "depends on shared state" do
    expect($coatepec_flaky_fixture_state).to eq(:primed)
  end
end
