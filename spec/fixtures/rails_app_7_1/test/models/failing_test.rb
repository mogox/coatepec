require "test_helper"

# Deliberately failing, targeted directly by path from coatepec's own
# integration specs -- same precedent as spec/failing_spec.rb.
class FailingTest < ActiveSupport::TestCase
  test "fails an assertion" do
    assert_equal 3, 1 + 1
  end

  test "raises" do
    raise "boom"
  end
end
