# Three examples raising the identical error; see test/failures/repeated_failure_test.rb.
RSpec.describe "repeated failure fixture" do
  it("raises first") { raise "the same boom" }
  it("raises second") { raise "the same boom" }
  it("raises third") { raise "the same boom" }
end
