# frozen_string_literal: true

require "spec_helper"
require "coatepec/introspection/route_entries"

# Mirrors the Struct fakes in routes_spec.rb: a route object that responds to
# nothing beyond `path`, as the plainest Journey route effectively does for
# RouteEntries' purposes. Proves the respond_to? guards hold for objects that
# know nothing about `internal` or `app`.
BareFakeRoute = Struct.new(:path_spec) do
  def path
    Struct.new(:spec).new(path_spec)
  end
end

RSpec.describe Coatepec::Introspection::RouteEntries do
  # RouteEntries reads exactly two things off a route -- `path.spec` and,
  # where present, `internal` / `app` -- so the doubles stub only those. Any
  # other message would raise, which is the point: nothing else is touched.
  def route(path, **extras)
    double(path: double(spec: path), **extras)
  end

  def mount(path, rack_app:, engine: true)
    route(path, app: double(engine?: engine, rack_app: rack_app))
  end

  # The mounted app Rails hands back IS the engine class itself, so `.name`
  # is the engine name and `.routes` is its RouteSet.
  def engine_class(name, inner_routes)
    route_set = double(routes: inner_routes)
    Class.new do
      define_singleton_method(:name) { name }
      define_singleton_method(:routes) { route_set }
    end
  end

  it "maps application routes in the given order with no engine and an unchanged path" do
    first = route("/widgets(.:format)")
    second = route("/owners(.:format)")

    entries = described_class.call([first, second])

    expect(entries.map(&:route)).to eq([first, second])
    expect(entries.map(&:path)).to eq(["/widgets(.:format)", "/owners(.:format)"])
    expect(entries.map(&:engine)).to eq([nil, nil])
  end

  it "handles routes that respond to neither internal nor app" do
    entries = described_class.call([BareFakeRoute.new("/widgets(.:format)")])

    expect(entries.map(&:path)).to eq(["/widgets(.:format)"])
    expect(entries.map(&:engine)).to eq([nil])
  end

  it "drops application routes flagged as internal" do
    kept = route("/widgets(.:format)", internal: false)
    entries = described_class.call([route("/rails/info(.:format)", internal: true), kept])

    expect(entries.map(&:route)).to eq([kept])
  end

  it "appends engine routes after every application route, prefixed with the mount path" do
    engine = engine_class("WidgetAdmin::Engine", [route("/audits(.:format)"), route("/audits/:id(.:format)")])
    routes = [route("/widgets(.:format)"), mount("/widget_admin(.:format)", rack_app: engine), route("/up(.:format)")]

    entries = described_class.call(routes)

    expect(entries.map(&:path)).to eq(
      ["/widgets(.:format)", "/widget_admin(.:format)", "/up(.:format)",
       "/widget_admin/audits(.:format)", "/widget_admin/audits/:id(.:format)"]
    )
    expect(entries.map(&:engine)).to eq([nil, nil, nil, "WidgetAdmin::Engine", "WidgetAdmin::Engine"])
  end

  it "names the engine after the mounted class itself rather than its class" do
    engine = engine_class("WidgetAdmin::Engine", [route("/audits(.:format)")])

    entries = described_class.call([mount("/widget_admin(.:format)", rack_app: engine)])

    expect(entries.last.engine).to eq("WidgetAdmin::Engine")
    expect(entries.last.engine).not_to eq("Class")
  end

  it "squeezes the duplicate slash of an engine mounted at the root" do
    engine = engine_class("WidgetAdmin::Engine", [route("/audits(.:format)")])

    entries = described_class.call([mount("/", rack_app: engine)])

    expect(entries.map(&:path)).to eq(["/", "/audits(.:format)"])
  end

  it "drops internal routes inside a mounted engine" do
    inner = route("/audits(.:format)", internal: false)
    engine = engine_class("WidgetAdmin::Engine", [route("/internal(.:format)", internal: true), inner])

    entries = described_class.call([mount("/widget_admin(.:format)", rack_app: engine)])

    expect(entries.map(&:route)).to eq([entries.first.route, inner])
    expect(entries.map(&:path)).to eq(["/widget_admin(.:format)", "/widget_admin/audits(.:format)"])
  end

  it "skips a mounted Rack app that is not an engine" do
    entries = described_class.call([mount("/sidekiq(.:format)", rack_app: Object.new, engine: false)])

    expect(entries.map(&:engine)).to eq([nil])
  end

  it "skips a mounted app that does not respond to engine?" do
    entries = described_class.call([route("/sidekiq(.:format)", app: Object.new)])

    expect(entries.map(&:engine)).to eq([nil])
  end

  it "skips an engine whose route set does not expose routes" do
    engine = Class.new do
      define_singleton_method(:name) { "Broken::Engine" }
      define_singleton_method(:routes) { Object.new }
    end

    # A raise here would fail the example on its own; the mount survives as a
    # plain application entry with nothing flattened underneath it.
    entries = described_class.call([mount("/broken(.:format)", rack_app: engine)])

    expect(entries.map(&:path)).to eq(["/broken(.:format)"])
    expect(entries.map(&:engine)).to eq([nil])
  end

  it "does not expand an engine mounted inside another engine" do
    inner_engine = engine_class("Nested::Engine", [route("/deep(.:format)")])
    outer = engine_class("WidgetAdmin::Engine", [mount("/nested(.:format)", rack_app: inner_engine)])

    entries = described_class.call([mount("/widget_admin(.:format)", rack_app: outer)])

    expect(entries.map(&:path)).to eq(["/widget_admin(.:format)", "/widget_admin/nested(.:format)"])
  end
end
