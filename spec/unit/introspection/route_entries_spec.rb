# frozen_string_literal: true

require "spec_helper"
require "coatepec/introspection/route_entries"

# A route that responds to nothing beyond `path`, proving the respond_to? guards
# hold for objects that know nothing about `internal` or `app`.
BareFakeRoute = Struct.new(:path_spec) do
  def path
    Struct.new(:spec).new(path_spec)
  end
end

RSpec.describe Coatepec::Introspection::RouteEntries do
  # Only a ::Rails::Engine subclass is expanded, so the fakes need a stand-in base class.
  before { stub_const("Rails::Engine", Class.new) }

  # Doubles stub only what RouteEntries reads; any other message raises, which is the point.
  def route(path, **extras)
    double(path: double(spec: path), **extras)
  end

  def mount(path, rack_app:, engine: true)
    route(path, app: double(engine?: engine, rack_app: rack_app))
  end

  # Rails hands back the engine class itself: `.name` is the engine name, `.routes` its RouteSet.
  def engine_class(name, inner_routes)
    route_set = double(routes: inner_routes)
    Class.new(Rails::Engine) do
      define_singleton_method(:name) { name }
      define_singleton_method(:routes) { route_set }
    end
  end

  it "maps application routes in the given order with no engine and the format suffix stripped" do
    first = route("/widgets(.:format)")
    second = route("/owners(.:format)")

    entries = described_class.call([first, second])

    expect(entries.map(&:route)).to eq([first, second])
    expect(entries.map(&:path)).to eq(["/widgets", "/owners"])
    expect(entries.map(&:engine)).to eq([nil, nil])
  end

  it "strips the optional format segment from every path" do
    entries = described_class.call([BareFakeRoute.new("/widgets(.:format)"), BareFakeRoute.new("/health")])

    expect(entries.map(&:path)).to eq(["/widgets", "/health"])
  end

  it "handles routes that respond to neither internal nor app" do
    entries = described_class.call([BareFakeRoute.new("/widgets(.:format)")])

    expect(entries.map(&:path)).to eq(["/widgets"])
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
      ["/widgets", "/widget_admin", "/up", "/widget_admin/audits", "/widget_admin/audits/:id"]
    )
    expect(entries.map(&:engine)).to eq([nil, nil, nil, "WidgetAdmin::Engine", "WidgetAdmin::Engine"])
  end

  it "names the engine after the mounted class itself rather than its class" do
    engine = engine_class("WidgetAdmin::Engine", [route("/audits(.:format)")])

    entries = described_class.call([mount("/widget_admin(.:format)", rack_app: engine)])

    expect(entries.last.engine).to eq("WidgetAdmin::Engine")
    expect(entries.last.engine).not_to eq("Class")
  end

  it "names an anonymous engine class with a fixed, deterministic fallback" do
    # Class.new(Rails::Engine) has a nil name; a fixed label keeps its routes tagged as engine routes.
    engine = engine_class(nil, [route("/audits(.:format)")])

    entries = described_class.call([mount("/anon(.:format)", rack_app: engine)])

    expect(entries.last.engine).to eq("(anonymous engine)")
  end

  it "collapses the duplicate slash of an engine mounted at the root" do
    engine = engine_class("WidgetAdmin::Engine", [route("/audits(.:format)")])

    entries = described_class.call([mount("/", rack_app: engine)])

    expect(entries.map(&:path)).to eq(["/", "/audits"])
  end

  it "drops internal routes inside a mounted engine" do
    inner = route("/audits(.:format)", internal: false)
    engine = engine_class("WidgetAdmin::Engine", [route("/internal(.:format)", internal: true), inner])
    mount_route = mount("/widget_admin(.:format)", rack_app: engine)

    entries = described_class.call([mount_route])

    expect(entries.map(&:route)).to eq([mount_route, inner])
    expect(entries.map(&:path)).to eq(["/widget_admin", "/widget_admin/audits"])
  end

  it "skips a mounted Rack app that is not an engine" do
    entries = described_class.call([mount("/sidekiq(.:format)", rack_app: Object.new, engine: false)])

    expect(entries.map(&:engine)).to eq([nil])
  end

  it "skips a mounted app that does not respond to engine?" do
    entries = described_class.call([route("/sidekiq(.:format)", app: Object.new)])

    expect(entries.map(&:engine)).to eq([nil])
  end

  it "never names or expands a class that answers engine? but is not a Rails::Engine" do
    impostor = Class.new
    expect(impostor).not_to receive(:name)
    expect(impostor).not_to receive(:routes)

    entries = described_class.call([mount("/impostor(.:format)", rack_app: impostor)])

    expect(entries.map(&:path)).to eq(["/impostor"])
    expect(entries.map(&:engine)).to eq([nil])
  end

  it "never calls name on a non-class rack app that answers engine?" do
    impostor = double("rack app")

    entries = described_class.call([mount("/impostor(.:format)", rack_app: impostor)])

    expect(entries.map(&:engine)).to eq([nil])
  end

  it "skips an engine whose route set does not expose routes" do
    engine = Class.new(Rails::Engine) do
      define_singleton_method(:name) { "Broken::Engine" }
      define_singleton_method(:routes) { Object.new }
    end

    # The mount survives as a plain application entry with nothing flattened underneath it.
    entries = described_class.call([mount("/broken(.:format)", rack_app: engine)])

    expect(entries.map(&:path)).to eq(["/broken"])
    expect(entries.map(&:engine)).to eq([nil])
  end

  it "does not expand an engine mounted inside another engine" do
    inner_engine = engine_class("Nested::Engine", [route("/deep(.:format)")])
    outer = engine_class("WidgetAdmin::Engine", [mount("/nested(.:format)", rack_app: inner_engine)])

    entries = described_class.call([mount("/widget_admin(.:format)", rack_app: outer)])

    expect(entries.map(&:path)).to eq(["/widget_admin", "/widget_admin/nested"])
  end
end
