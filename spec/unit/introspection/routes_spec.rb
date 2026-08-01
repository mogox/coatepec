# frozen_string_literal: true

require "spec_helper"
require "coatepec/introspection/routes"

FakeRoute = Struct.new(:name, :verb, :path_spec, :defaults) do
  def path
    Struct.new(:spec).new(path_spec)
  end
end

RSpec.describe Coatepec::Introspection::Routes do
  def stub_routes(routes)
    allow(described_class).to receive(:rails_routes).and_return(routes)
  end

  it "maps route fields including controller/action from defaults" do
    routes = [FakeRoute.new("widgets", "GET", "/widgets(.:format)", { controller: "widgets", action: "index" })]
    stub_routes(routes)

    result = described_class.new.call

    expect(result[:items]).to eq(
      [{ name: "widgets", verb: "GET", path: "/widgets(.:format)", controller: "widgets", action: "index" }]
    )
    expect(result[:matched]).to eq(1)
  end

  it "filters case-insensitively across all fields when query is given" do
    routes = [
      FakeRoute.new("widgets", "GET", "/widgets(.:format)", { controller: "widgets", action: "index" }),
      FakeRoute.new("owners", "GET", "/owners(.:format)", { controller: "owners", action: "index" })
    ]
    stub_routes(routes)

    result = described_class.new(query: "WIDGET").call

    expect(result[:items].map { |r| r[:name] }).to eq(["widgets"])
    expect(result[:matched]).to eq(1)
  end

  it "paginates with limit and offset while matched reflects the full filtered count" do
    routes = (1..5).map { |i| FakeRoute.new("route#{i}", "GET", "/r#{i}", { controller: "c", action: "a" }) }
    stub_routes(routes)

    result = described_class.new(limit: 2, offset: 1).call

    expect(result[:items].map { |r| r[:name] }).to eq(%w[route2 route3])
    expect(result[:matched]).to eq(5)
    expect(result[:limit]).to eq(2)
    expect(result[:offset]).to eq(1)
  end

  it "caps limit at 200 even if a larger value is requested" do
    routes = (1..3).map { |i| FakeRoute.new("route#{i}", "GET", "/r#{i}", { controller: "c", action: "a" }) }
    stub_routes(routes)

    result = described_class.new(limit: 500).call

    expect(result[:limit]).to eq(200)
  end
end
