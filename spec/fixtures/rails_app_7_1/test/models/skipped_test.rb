require "test_helper"

class SkippedTest < ActiveSupport::TestCase
  test "is skipped" do
    skip "not yet"
  end
end
