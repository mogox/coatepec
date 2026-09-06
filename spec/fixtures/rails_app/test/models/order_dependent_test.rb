require "test_helper"

# Deliberately order-dependent: "depends on shared state" passes only when
# "primes the shared state" ran first under the current --seed. Exists so
# FlakyChecker's Minitest integration test has a genuine flaky test to
# detect; each coatepec run is a fresh child process, so the global starts
# nil every round. Mirrors spec/flaky_fixture_spec.rb.
class OrderDependentTest < ActiveSupport::TestCase
  test "primes the shared state" do
    $coatepec_flaky_fixture_state = :primed

    assert_equal :primed, $coatepec_flaky_fixture_state
  end

  test "depends on shared state" do
    assert_equal :primed, $coatepec_flaky_fixture_state
  end
end
