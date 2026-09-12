# frozen_string_literal: true

require "spec_helper"
require "coatepec/introspection/controller"

# Introspection::Controller resolves constants through ActiveSupport and
# reflects over real ActionController classes, relying on Rails already being
# booted in this gem's real architecture. These examples build genuine
# controller classes instead of doubles -- the whole point is to assert
# against Rails' actual reflection APIs, which a double would not exercise.
# actionpack is guaranteed present: railties (a declared runtime dependency,
# ">= 7.1", "< 8.2") depends on actionpack at the same version.
require "action_controller"
require "json"
require "active_support/inflector"

module ControllerFixtures
  module Auditable
    extend ActiveSupport::Concern
    # Deliberately public: Rails treats any public method as routable, so this
    # must surface in `actions`. See "action_methods reports a concern's public
    # method" in the design doc.
    def audit; end
  end

  module Throttled; end

  class BaseController < ActionController::Base; end

  class WidgetsController < BaseController
    include Auditable

    before_action :require_login, only: %i[edit update]
    before_action :set_widget, except: [:index]
    around_action :with_timing
    after_action :notify, if: :notifiable?
    after_action :audit_trail, if: -> { true }
    before_action { head :ok }
    # only: naming an action this controller does not define at all -- the
    # exact drift the design doc devotes a paragraph to. This must be
    # reported, never raised: CallbackProbe hardcodes
    # raise_on_missing_callback_actions to false specifically so this doesn't
    # blow up as ActionNotFound.
    before_action :ghost_guard, only: [:vanished]

    def index; end
    def show; end
    def edit; end
    def update; end
    def orphaned; end

    private

    def require_login; end
    def set_widget; end
    def with_timing; end
    def notify; end
    def audit_trail; end
    def ghost_guard; end

    def notifiable?
      raise "callbacks must never be executed during introspection"
    end
  end

  # Two ActionFilters land in one callback's @if chain whenever a
  # skip_before_action's only:/except: layers onto an existing only:/except:
  # -- ActiveSupport::Callbacks::Callback#merge_conditional_options
  # concatenates rather than replaces. Three shapes, matching the whole-branch
  # review's three verified-wrong-today examples.
  class ExceptThenSkipOnlyController < ActionController::Base
    before_action :require_login, except: [:health]
    skip_before_action :require_login, only: [:public_index]

    def health; end
    def public_index; end

    private

    def require_login; end
  end

  class SkipOnlyTwiceController < ActionController::Base
    before_action :authenticate!
    skip_before_action :authenticate!, only: [:index]
    skip_before_action :authenticate!, only: [:show]

    def index; end
    def show; end

    private

    def authenticate!; end
  end

  class OnlyThenSkipExceptController < ActionController::Base
    before_action :require_login, only: %i[edit update]
    skip_before_action :require_login, except: [:other]

    def edit; end
    def update; end
    def other; end

    private

    def require_login; end
  end

  # A bare Metal subclass does not include AbstractController::Callbacks (only
  # Base and API do), so it has no _process_action_callbacks at all -- but it
  # still passes the class gate, which deliberately admits every Metal
  # descendant.
  class HealthController < ActionController::Metal
    def show
      self.response_body = "ok"
    end
  end

  class ThingsController < ActionController::API
    include Throttled
    def index; end
  end

  class NotAController; end

  # An anonymous filter class (no assigned constant, so #name is nil) has to
  # fall back to a stable non-nil String in filter_description -- the
  # documented contract is that `filter` is always a String.
  class AnonymousFilterController < ActionController::Base
    before_action Class.new { def before(_controller); end }.new
    def index; end
  end

  # Mirrors the real route objects' surface: Introspection::Routes reads
  # exactly these (verb, path.spec, name, defaults) off each route, so a
  # struct with the same shape exercises the same code path without a boot.
  FakePath = Struct.new(:spec)
  FakeRoute = Struct.new(:verb, :path, :name, :defaults)

  # A mount route adds exactly one member to that surface: `app`, off which
  # RouteEntries reads `engine?` and `rack_app`. Keeping it a separate struct
  # leaves FakeRoute free of an `app` member, so the plain-route examples keep
  # proving RouteEntries' respond_to? guard for routes that have none.
  FakeMountedApp = Struct.new(:rack_app) do
    def engine?
      true
    end
  end
  FakeMountRoute = Struct.new(:verb, :path, :name, :defaults, :app)

  # The controller an engine's own route set reaches. `export` is deliberately
  # unrouted, so it must still be reported as unroutable even once the engine's
  # routes are cross-referenced.
  class EngineAuditsController < ActionController::Base
    def index; end
    def show; end
    def export; end
  end

  # 250 real action methods, each with a real route -- more than MAX_ITEMS.
  # `actions` in the response is truncated to the first 200 (alphabetically),
  # so routes reaching action_201..action_250 must not be misreported as
  # routes_without_action just because those actions fell past the
  # truncation point in the *displayed* list.
  class ManyActionsController < ActionController::Base
    (1..250).each { |i| define_method(format("action_%03d", i)) {} }
  end
end

RSpec.describe Coatepec::Introspection::Controller do
  # Controller.rails_routes reaches Rails.application.routes.routes, which is
  # only reachable with a real, booted application -- unreachable in this
  # unit spec process, exactly as for Introspection::Routes. Every example
  # that calls #call needs it stubbed; this default covers the examples that
  # don't care about route data. The "route cross-referencing" block below
  # overrides it with real route fixtures for its own examples.
  before { allow(described_class).to receive(:rails_routes).and_return([]) }

  describe "name validation" do
    it "raises invalid_controller_name for a lowercase-starting name" do
      expect { described_class.new("widgetsController").call }
        .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:invalid_controller_name) }
    end

    it "raises invalid_controller_name for a name containing invalid characters" do
      expect { described_class.new("WidgetsController; puts 1").call }
        .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:invalid_controller_name) }
    end

    it "raises invalid_controller_name for non-String and empty input" do
      [nil, 123, ""].each do |bad_name|
        expect { described_class.new(bad_name).call }
          .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:invalid_controller_name) }
      end
    end

    it "accepts a well-formed namespaced name (failing later, on resolution)" do
      expect { described_class.new("Admin::NopeController").call }
        .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:controller_not_found) }
    end
  end

  describe "class gating" do
    it "raises not_action_controller for a plain class" do
      expect { described_class.new("ControllerFixtures::NotAController").call }
        .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:not_action_controller) }
    end

    it "accepts an ActionController::API controller" do
      result = described_class.new("ControllerFixtures::ThingsController").call
      expect(result[:name]).to eq("ControllerFixtures::ThingsController")
    end

    it "accepts a bare ActionController::Metal subclass without crashing" do
      result = described_class.new("ControllerFixtures::HealthController").call
      expect(result[:name]).to eq("ControllerFixtures::HealthController")
      expect(result[:controller_path]).to eq("controller_fixtures/health")
      expect(result[:actions].map { |a| a[:name] }).to eq(["show"])
      # Metal does not include AbstractController::Callbacks (only Base and
      # API do), so it has no _process_action_callbacks at all -- must be
      # reported as an empty list, not raise NoMethodError.
      expect(result[:callbacks]).to eq([])
    end
  end

  describe "actions" do
    subject(:result) { described_class.new("ControllerFixtures::WidgetsController").call }

    it "returns the controller's action names, sorted" do
      expect(result[:actions].map { |a| a[:name] })
        .to eq(%w[audit edit index orphaned show update])
    end

    it "reports controller_path" do
      expect(result[:controller_path]).to eq("controller_fixtures/widgets")
    end
  end

  describe "concerns" do
    it "includes both own and inherited app concerns, and no framework modules" do
      result = described_class.new("ControllerFixtures::WidgetsController").call
      expect(result[:concerns]).to eq(["ControllerFixtures::Auditable"])
      expect(result[:concerns].grep(/^ActionController::/)).to be_empty
    end

    it "slices at ActionController::API for an API controller" do
      result = described_class.new("ControllerFixtures::ThingsController").call
      expect(result[:concerns]).to eq(["ControllerFixtures::Throttled"])
    end
  end

  describe "callbacks" do
    subject(:callbacks) { described_class.new("ControllerFixtures::WidgetsController").call[:callbacks] }

    def callback_for(filter)
      callbacks.find { |cb| cb[:filter] == filter }
    end

    it "reports kind and a symbol filter by name" do
      expect(callback_for("require_login")[:kind]).to eq("before")
      expect(callback_for("with_timing")[:kind]).to eq("around")
    end

    # Load-bearing, not incidental: reaching @if/@unless needs a private ivar
    # read, and if a future Rails renames them, Array(nil) would silently
    # report every callback as unconditional. This assertion is what turns
    # that silent degradation into a loud CI failure.
    it "resolves only: to its action list" do
      expect(callback_for("require_login")[:only]).to eq(%w[edit update])
      expect(callback_for("require_login")[:except]).to be_nil
    end

    it "resolves except: to its action list, preserving author intent" do
      expect(callback_for("set_widget")[:except]).to eq(["index"])
      expect(callback_for("set_widget")[:only]).to be_nil
    end

    it "reports a Symbol if: condition by name" do
      expect(callback_for("notify")[:if]).to eq(["notifiable?"])
    end

    it "reports a Proc if: condition as (block), never its source path" do
      expect(callback_for("audit_trail")[:if]).to eq(["(block)"])
    end

    it "reports a block filter as (block)" do
      expect(callback_for("(block)")).not_to be_nil
    end

    it "leaves unconditional callbacks with empty conditions" do
      expect(callback_for("with_timing")).to include(only: nil, except: nil, if: [], unless: [])
    end

    it "never serializes a filesystem path anywhere in the response" do
      json = JSON.generate(described_class.new("ControllerFixtures::WidgetsController").call)
      expect(json).not_to include(__dir__)
      expect(json).not_to match(%r{/[\w.-]+/[\w.-]+\.rb})
    end

    it "does not execute callback conditions" do
      # notifiable? raises if called. Reaching this line at all proves it wasn't.
      expect { described_class.new("ControllerFixtures::WidgetsController").call }.not_to raise_error
    end

    it "falls back to a stable non-nil String for an anonymous filter class" do
      callbacks = described_class.new("ControllerFixtures::AnonymousFilterController").call[:callbacks]
      expect(callbacks).not_to be_empty
      callbacks.each { |cb| expect(cb[:filter]).to be_a(String) }
    end

    # Flipping CallbackProbe's hardcoded `raise_on_missing_callback_actions:
    # false` to `true` must fail this, not any test above: ActionFilter#match?
    # raises ActionNotFound when it's true and an only:/except: names an
    # action the controller doesn't define -- exactly the drift this tool
    # exists to report, so it must be reported, never raised.
    it "reports sensibly, without raising, when only: names an action the controller doesn't define" do
      expect { callbacks }.not_to raise_error
      expect(callback_for("ghost_guard")[:only]).to eq([])
    end
  end

  describe "only:/except: spanning more than one ActionFilter in a chain" do
    # skip_before_action's only:/except: concatenates onto the callback's
    # existing @if/@unless chain instead of replacing it
    # (ActiveSupport::Callbacks::Callback#merge_conditional_options), so a
    # naive `find` that keeps only the first ActionFilter in the chain
    # silently drops every skip layered on top of it -- always biasing
    # toward *over*-reporting protection.
    def callback_for(klass_name, filter)
      described_class.new(klass_name).call[:callbacks].find { |cb| cb[:filter] == filter }
    end

    it "unions except: across a parent's except: and a child's skip only:, both landing in @unless" do
      cb = callback_for("ControllerFixtures::ExceptThenSkipOnlyController", "require_login")
      expect(cb[:except]).to eq(%w[health public_index])
      expect(cb[:only]).to be_nil
    end

    it "unions except: across two sequential skip only:s, both landing in @unless" do
      cb = callback_for("ControllerFixtures::SkipOnlyTwiceController", "authenticate!")
      expect(cb[:except]).to eq(%w[index show])
      expect(cb[:only]).to be_nil
    end

    it "intersects only: across a parent's only: and a child's skip except:, both landing in @if" do
      cb = callback_for("ControllerFixtures::OnlyThenSkipExceptController", "require_login")
      expect(cb[:only]).to eq([])
      expect(cb[:except]).to be_nil
    end
  end

  describe "route cross-referencing" do
    def fake_route(verb, path, name, controller, action)
      ControllerFixtures::FakeRoute.new(
        verb, ControllerFixtures::FakePath.new(path), name,
        { controller: controller, action: action }
      )
    end

    let(:routes) do
      [
        fake_route("GET", "/controller_fixtures/widgets(.:format)", "widgets", "controller_fixtures/widgets", "index"),
        fake_route("GET", "/controller_fixtures/widgets/:id(.:format)", "widget", "controller_fixtures/widgets",
                   "show"),
        fake_route("PATCH", "/controller_fixtures/widgets/:id(.:format)", nil, "controller_fixtures/widgets",
                   "update"),
        fake_route("PUT", "/controller_fixtures/widgets/:id(.:format)", nil, "controller_fixtures/widgets", "update"),
        fake_route("GET", "/controller_fixtures/widgets/legacy(.:format)", nil, "controller_fixtures/widgets",
                   "removed_long_ago"),
        fake_route("GET", "/other(.:format)", nil, "other", "index"),
        # A mount/redirect route has no controller or action at all.
        fake_route("GET", "/up(.:format)", nil, nil, nil)
      ]
    end

    subject(:result) do
      allow(described_class).to receive(:rails_routes).and_return(routes)
      described_class.new("ControllerFixtures::WidgetsController").call
    end

    def action(name)
      result[:actions].find { |a| a[:name] == name }
    end

    it "attaches the matching route to an action" do
      expect(action("index")[:routes])
        .to eq([{ verb: "GET", path: "/controller_fixtures/widgets(.:format)", route_name: "widgets" }])
    end

    it "attaches every route reaching one action" do
      expect(action("update")[:routes].map { |r| r[:verb] }).to eq(%w[PATCH PUT])
      expect(action("update")[:routes].map { |r| r[:route_name] }).to eq([nil, nil])
    end

    it "keeps the raw path spec so it matches rails_routes byte-for-byte" do
      expect(action("show")[:routes].first[:path]).to eq("/controller_fixtures/widgets/:id(.:format)")
    end

    it "reports an action no route reaches as unroutable" do
      expect(action("orphaned")[:routes]).to eq([])
      expect(result[:unroutable_actions]).to include("orphaned")
      expect(result[:unroutable_actions]).not_to include("index")
    end

    it "reports a route naming an action the controller does not define" do
      expect(result[:routes_without_action]).to eq(["removed_long_ago"])
    end

    it "ignores routes belonging to other controllers and routes with no controller" do
      all_paths = result[:actions].flat_map { |a| a[:routes] }.map { |r| r[:path] }
      expect(all_paths).not_to include("/other(.:format)", "/up(.:format)")
    end

    # The mounted app Rails hands back IS the engine class itself, so `.name`
    # is the engine name and `.routes` is its RouteSet, whose own `.routes` is
    # the enumerable of routes drawn inside the engine.
    def fake_engine(name, inner_routes)
      route_set = Struct.new(:routes).new(inner_routes)
      Class.new do
        define_singleton_method(:name) { name }
        define_singleton_method(:routes) { route_set }
      end
    end

    def fake_mount(path, engine)
      ControllerFixtures::FakeMountRoute.new(
        "", ControllerFixtures::FakePath.new(path), nil, {},
        ControllerFixtures::FakeMountedApp.new(engine)
      )
    end

    it "cross-references a controller reached only through a mounted engine" do
      engine = fake_engine("WidgetAdmin::Engine", [
                             fake_route("GET", "/audits(.:format)", "audits",
                                        "controller_fixtures/engine_audits", "index"),
                             fake_route("GET", "/audits/:id(.:format)", "audit",
                                        "controller_fixtures/engine_audits", "show")
                           ])
      allow(described_class).to receive(:rails_routes).and_return(routes + [fake_mount("/widget_admin", engine)])

      engine_result = described_class.new("ControllerFixtures::EngineAuditsController").call

      index = engine_result[:actions].find { |a| a[:name] == "index" }
      # The mount prefix is on the path, exactly as rails_routes reports it.
      expect(index[:routes]).to eq([{ verb: "GET", path: "/widget_admin/audits(.:format)", route_name: "audits" }])
      expect(engine_result[:actions].find { |a| a[:name] == "show" }[:routes].first[:path])
        .to eq("/widget_admin/audits/:id(.:format)")
      expect(engine_result[:unroutable_actions]).to eq(["export"])
      expect(engine_result[:routes_without_action]).to eq([])
    end
  end

  describe "truncation" do
    it "does not report a real, routed action as routes_without_action just because the action list was truncated" do
      routes = (1..250).map do |i|
        action = format("action_%03d", i)
        fake_route("GET", "/many/#{action}(.:format)", nil, "controller_fixtures/many_actions", action)
      end
      allow(described_class).to receive(:rails_routes).and_return(routes)

      result = described_class.new("ControllerFixtures::ManyActionsController").call

      # actions[] itself is truncated to MAX_ITEMS (200), same as every other
      # collection -- action_201..action_250 do not appear here.
      expect(result[:actions].size).to eq(200)
      # ...but every one of the 250 actions has a real route, so nothing
      # should be reported as a route naming a nonexistent action, even
      # though 50 of those routes' actions fell past the truncation point in
      # the displayed `actions` list above.
      expect(result[:routes_without_action]).to eq([])
    end

    def fake_route(verb, path, name, controller, action)
      ControllerFixtures::FakeRoute.new(
        verb, ControllerFixtures::FakePath.new(path), name,
        { controller: controller, action: action }
      )
    end
  end
end
