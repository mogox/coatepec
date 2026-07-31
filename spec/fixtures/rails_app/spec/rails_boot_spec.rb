require "rails_helper"

RSpec.describe "Rails boot" do
  it "has Rails loaded in the test environment" do
    expect(defined?(Rails)).to be_truthy
    expect(Rails.env).to eq("test")
  end

  it "can execute a trivial query against the test database" do
    result = ActiveRecord::Base.connection.execute("SELECT 1")
    expect(result.to_a).not_to be_empty
  end
end
