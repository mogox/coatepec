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

  # Only a ::Rails::Engine subclass is expanded, so the fake needs a stand-in base class.
  before { stub_const("Rails::Engine", Class.new) }

  # Rails hands back the engine class itself, whose .routes is a RouteSet wrapping its own routes.
  def engine_class(name, inner_routes)
    route_set = double(routes: inner_routes)
    Class.new(Rails::Engine) do
      define_singleton_method(:name) { name }
      define_singleton_method(:routes) { route_set }
    end
  end

  it "maps route fields including controller/action from defaults" do
    routes = [FakeRoute.new("widgets", "GET", "/widgets(.:format)", { controller: "widgets", action: "index" })]
    stub_routes(routes)

    result = described_class.new.call

    expect(result[:items]).to eq(
      [{ name: "widgets", verb: "GET", path: "/widgets(.:format)", controller: "widgets", action: "index",
         engine: nil }]
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
    expect(result[:next_offset]).to eq(3)
  end

  it "reports a nil next_offset on the last page and defaults the limit to 100" do
    routes = (1..3).map { |i| FakeRoute.new("route#{i}", "GET", "/r#{i}", { controller: "c", action: "a" }) }
    stub_routes(routes)

    result = described_class.new.call

    expect(result[:limit]).to eq(100)
    expect(result[:next_offset]).to be_nil
  end

  # A zero limit returns nothing, so a next_offset equal to the current one would page forever.
  it "reports a nil next_offset when the limit is zero" do
    routes = (1..3).map { |i| FakeRoute.new("route#{i}", "GET", "/r#{i}", { controller: "c", action: "a" }) }
    stub_routes(routes)

    result = described_class.new(limit: 0).call

    expect(result[:items]).to eq([])
    expect(result[:next_offset]).to be_nil
  end

  it "reports routes mounted inside an engine, tagged with the engine name" do
    inner = FakeRoute.new("audits", "GET", "/audits(.:format)",
                          { controller: "widget_admin/audits", action: "index" })
    engine = engine_class("WidgetAdmin::Engine", [inner])
    mount = double(name: "widget_admin", verb: "", path: double(spec: "/widget_admin"), defaults: {},
                   app: double(engine?: true, rack_app: engine))
    stub_routes([FakeRoute.new("widgets", "GET", "/widgets(.:format)", { controller: "widgets", action: "index" }),
                 mount])

    result = described_class.new(engines: "include").call

    expect(result[:items].last).to eq(
      { name: "audits", verb: "GET", path: "/widget_admin/audits(.:format)",
        controller: "widget_admin/audits", action: "index", engine: "WidgetAdmin::Engine" }
    )
  end

  # The query filter searches every value of an item, so the engine name is
  # matchable for free -- no special-casing needed for "show me engine X".
  it "matches on the engine field when a query is given" do
    engine = engine_class("WidgetAdmin::Engine", [FakeRoute.new("audits", "GET", "/audits(.:format)", {})])
    stub_routes([FakeRoute.new("widgets", "GET", "/widgets(.:format)", { controller: "widgets", action: "index" }),
                 double(name: nil, verb: "", path: double(spec: "/widget_admin"), defaults: {},
                        app: double(engine?: true, rack_app: engine))])

    result = described_class.new(query: "widgetadmin", engines: "include").call

    expect(result[:matched]).to eq(1)
    expect(result[:items].map { |r| r[:engine] }).to eq(["WidgetAdmin::Engine"])
  end

  it "caps limit at 200 even if a larger value is requested" do
    routes = (1..3).map { |i| FakeRoute.new("route#{i}", "GET", "/r#{i}", { controller: "c", action: "a" }) }
    stub_routes(routes)

    result = described_class.new(limit: 500).call

    expect(result[:limit]).to eq(200)
  end

  def app_and_engine_routes
    inner = FakeRoute.new("audits", "GET", "/audits(.:format)", { controller: "widget_admin/audits", action: "index" })
    engine = engine_class("WidgetAdmin::Engine", [inner])
    stub_routes([FakeRoute.new("widgets", "GET", "/widgets(.:format)", { controller: "widgets", action: "index" }),
                 double(name: "widget_admin", verb: "", path: double(spec: "/widget_admin"), defaults: {},
                        app: double(engine?: true, rack_app: engine))])
  end

  # Two engine routes, so a query that matches only one shows engines_excluded is query-scoped, not a total.
  def app_and_two_engine_routes
    engine = engine_class("WidgetAdmin::Engine", [
                            FakeRoute.new("audits", "GET", "/audits(.:format)",
                                          { controller: "widget_admin/audits", action: "index" }),
                            FakeRoute.new("settings", "GET", "/settings(.:format)",
                                          { controller: "widget_admin/settings", action: "show" })
                          ])
    stub_routes([FakeRoute.new("widgets", "GET", "/widgets(.:format)", { controller: "widgets", action: "index" }),
                 double(name: "widget_admin", verb: "", path: double(spec: "/widget_admin"), defaults: {},
                        app: double(engine?: true, rack_app: engine))])
  end

  it "withholds engine routes by default and reports how many" do
    app_and_engine_routes

    result = described_class.new.call

    expect(result[:items].map { |r| r[:name] }).to eq(%w[widgets widget_admin])
    expect(result[:engines]).to eq("exclude")
    expect(result[:engines_excluded]).to eq(1)
    expect(result.keys).to eq(%i[items matched limit offset next_offset engines engines_excluded])
  end

  it "includes engine routes and reports zero excluded when engines is include" do
    app_and_engine_routes

    result = described_class.new(engines: "include").call

    expect(result[:items].map { |r| r[:name] }).to eq(%w[widgets widget_admin audits])
    expect(result).to include(engines: "include", engines_excluded: 0)
  end

  # The count is of withheld routes that matched the query, so a caller knows what this exact call hid.
  it "counts only withheld routes that match the query" do
    app_and_engine_routes

    result = described_class.new(query: "audit").call

    expect(result[:items]).to eq([])
    expect(result[:matched]).to eq(0)
    expect(result[:engines_excluded]).to eq(1)
  end

  it "counts withheld routes against the query, not the whole engine" do
    app_and_two_engine_routes

    result = described_class.new(query: "audit").call

    expect(result[:engines_excluded]).to eq(1)
    expect(described_class.new(engines: "include").call[:engines_excluded]).to eq(0)
    expect(described_class.new.call[:engines_excluded]).to eq(2)
  end

  it "returns application routes only, mount route included, when engines is exclude" do
    app_and_engine_routes

    result = described_class.new(engines: "exclude").call

    expect(result[:items].map { |r| r[:name] }).to eq(%w[widgets widget_admin])
    expect(result[:matched]).to eq(2)
    expect(result[:engines_excluded]).to eq(1)
  end

  it "returns engine routes only when engines is only" do
    app_and_engine_routes

    result = described_class.new(engines: "only").call

    expect(result[:items].map { |r| r[:name] }).to eq(%w[audits])
    expect(result[:matched]).to eq(1)
    expect(result).to include(engines: "only", engines_excluded: 2)
  end

  # The query runs first so matched/next_offset describe the kept page and engines_excluded this query's omissions.
  it "applies the engine filter after the query match and before the page" do
    app_and_engine_routes

    result = described_class.new(query: "widget", engines: "exclude", limit: 1).call

    expect(result[:items].map { |r| r[:name] }).to eq(%w[widgets])
    expect(result[:matched]).to eq(2)
    expect(result[:next_offset]).to eq(1)
    expect(result[:engines_excluded]).to eq(1)
  end

  it "rejects an unknown engines value" do
    stub_routes([])

    expect { described_class.new(engines: "some") }
      .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:invalid_engines_filter) }
  end
end
