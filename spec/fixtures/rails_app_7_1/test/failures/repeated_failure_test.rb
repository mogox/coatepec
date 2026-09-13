require "test_helper"

# Three tests raising the identical error, targeted directly by path from coatepec's own
# integration specs: the failure collapser must emit the error once and roll the rest up.
class RepeatedFailureTest < ActiveSupport::TestCase
  test "raises first" do
    raise "the same boom"
  end

  test "raises second" do
    raise "the same boom"
  end

  test "raises third" do
    raise "the same boom"
  end
end
