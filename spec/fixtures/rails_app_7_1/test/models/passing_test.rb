require "test_helper"

class PassingTest < ActiveSupport::TestCase
  test "adds" do
    assert_equal 2, 1 + 1
  end

  # line 8 is this comment; the next line is 9 -- coatepec's own specs select it by file:9
  test "reaches the database" do
    assert Widget.count >= 0
  end
end
