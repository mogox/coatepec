RSpec.describe "slow fixture" do
  it "sleeps past a short timeout" do
    sleep 2
    expect(true).to be(true)
  end
end
