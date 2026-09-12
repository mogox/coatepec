# frozen_string_literal: true

require "spec_helper"

RSpec.describe Coatepec::Introspection::Controller, type: :integration do
  def run_controller_call(name)
    lib_path = File.expand_path("../../../lib", __dir__)
    run_in_fixture_app(<<~RUBY)
      $LOAD_PATH.unshift(#{lib_path.inspect})
      require "coatepec"
      Coatepec::Worker::RailsRuntime.new(#{FIXTURE_APP_ROOT.inspect}).boot!
      puts JSON.generate(Coatepec::Introspection::Controller.new(#{name.inspect}).call)
    RUBY
  end

  def result_for(name)
    stdout, stderr, status = run_controller_call(name)
    expect(status).to be_success, stderr
    JSON.parse(stdout.lines.last)
  end

  it "returns WidgetsController's actions, including a concern's public method" do
    result = result_for("WidgetsController")

    expect(result["name"]).to eq("WidgetsController")
    expect(result["controller_path"]).to eq("widgets")
    expect(result["actions"].map { |a| a["name"] })
      .to include("audit", "edit", "index", "orphaned", "show", "update")
  end

  it "resolves only:/except: against the real callback chain" do
    callbacks = result_for("WidgetsController")["callbacks"]

    require_login = callbacks.find { |cb| cb["filter"] == "require_login" }
    expect(require_login["only"]).to eq(%w[edit update])
    expect(require_login["except"]).to be_nil

    set_widget = callbacks.find { |cb| cb["filter"] == "set_widget" }
    expect(set_widget["except"]).to eq(["index"])
    expect(set_widget["only"]).to be_nil
  end

  it "collects a real anonymous block callback and one contributed by a concern's included block" do
    callbacks = result_for("WidgetsController")["callbacks"]

    # `before_action(if: :widgets_own_block?) { head :ok }` -- a genuine
    # Rails-built anonymous callback, not a stubbed Proc, proving it is
    # reduced to "(block)" and never leaks Proc#to_s's absolute source path.
    # Anchored on the if: condition's method name, unique to this fixture's
    # own callback, rather than on filter == "(block)" alone: on Rails 8.1,
    # ApplicationController's `allow_browser versions: :modern` itself
    # compiles to a second, unconditional `before_action -> { ... }`, so
    # WidgetsController's real chain carries two "(block)" filters there --
    # `include("(block)")` alone would still pass with this fixture's own
    # block deleted. This holds identically on 7.1 (where allow_browser
    # doesn't exist) because it is not counting "(block)" filters at all.
    widgets_block = callbacks.find { |cb| cb["if"] == ["widgets_own_block?"] }
    expect(widgets_block).not_to be_nil
    expect(widgets_block["filter"]).to eq("(block)")

    # `record_audit`, registered by Auditable's `included do before_action
    # :record_audit end`, proving callbacks contributed by a concern are
    # collected from the real _process_action_callbacks chain, not just ones
    # declared directly on the controller.
    expect(callbacks.map { |cb| cb["filter"] }).to include("record_audit")
  end

  it "names a Symbol condition but reduces a Proc condition to (block)" do
    callbacks = result_for("WidgetsController")["callbacks"]

    expect(callbacks.find { |cb| cb["filter"] == "notify" }["if"]).to eq(["notifiable?"])
    expect(callbacks.find { |cb| cb["filter"] == "audit_trail" }["if"]).to eq(["(block)"])
  end

  it "never leaks a filesystem path, and never executes a callback condition" do
    # WidgetsController#notifiable? raises when called, so a successful call
    # is itself proof the condition was not executed.
    stdout, stderr, status = run_controller_call("WidgetsController")
    expect(status).to be_success, stderr

    json = stdout.lines.last
    expect(json).not_to include(FIXTURE_APP_ROOT)
    expect(json).not_to include("callback conditions must never be executed")
  end

  it "cross-references real routes, including multi-verb and missing ones" do
    result = result_for("WidgetsController")

    index = result["actions"].find { |a| a["name"] == "index" }
    expect(index["routes"].map { |r| r["verb"] }).to eq(["GET"])
    expect(index["routes"].first["path"]).to eq("/widgets(.:format)")
    # An application route carries a null engine, the same marker rails_routes
    # reports for it.
    expect(index["routes"].first["engine"]).to be_nil

    update = result["actions"].find { |a| a["name"] == "update" }
    expect(update["routes"].map { |r| r["verb"] }).to contain_exactly("PATCH", "PUT")

    # "orphaned" has no route at all; "audit" (Auditable's public method) is
    # also unroutable, since routes.rb only routes index/show/edit/update.
    # Exact-set, not include(), so a regression that dropped "audit" while
    # keeping "orphaned" cannot pass.
    expect(result["unroutable_actions"]).to contain_exactly("audit", "orphaned")
    expect(result["routes_without_action"]).to eq(["removed_long_ago"])
  end

  it "handles a namespaced controller's controller_path and routes" do
    result = result_for("Admin::ReportsController")

    expect(result["controller_path"]).to eq("admin/reports")
    index = result["actions"].find { |a| a["name"] == "index" }
    expect(index["routes"].first["path"]).to eq("/admin/reports(.:format)")
  end

  it "cross-references a controller inside a mounted engine against the engine's own routes" do
    result = result_for("WidgetAdmin::AuditsController")

    expect(result["controller_path"]).to eq("widget_admin/audits")

    index = result["actions"].find { |a| a["name"] == "index" }
    # The mount point is on the path, so this is byte-identical to the same
    # route's path from rails_routes, and `engine` names the engine it came
    # from rather than leaving it to be mistaken for an application route.
    expect(index["routes"])
      .to eq([{ "verb" => "GET", "path" => "/widget_admin/audits(.:format)", "route_name" => "audits",
                "engine" => "WidgetAdmin::Engine" }])

    show = result["actions"].find { |a| a["name"] == "show" }
    expect(show["routes"].first["path"]).to eq("/widget_admin/audits/:id(.:format)")

    # The engine routes index/show only, so `export` is genuinely unroutable
    # -- it must not be swept up by the engine's routes now being visible.
    expect(result["unroutable_actions"]).to eq(["export"])
    expect(result["routes_without_action"]).to eq([])
  end

  it "reports app concerns without framework modules, including one inherited from ApplicationController" do
    concerns = result_for("WidgetsController")["concerns"]

    expect(concerns).to include("Auditable", "Traceable")
    expect(concerns.grep(/^(ActionController|AbstractController|ActiveSupport)::/)).to be_empty
  end

  it "introspects an ActionController::API controller" do
    result = result_for("PingsController")

    expect(result["controller_path"]).to eq("pings")
    expect(result["actions"].map { |a| a["name"] }).to include("index")
    index = result["actions"].find { |a| a["name"] == "index" }
    expect(index["routes"].first["path"]).to eq("/pings(.:format)")

    # Proves the concern slice resolves to ActionController::API for an
    # API-only controller, not just ActionController::Base: if framework_base
    # failed to match ActionController::API, concerns_for's take_while would
    # run unterminated and return up to 200 framework module names instead.
    concerns = result["concerns"]
    expect(concerns.grep(/^(ActionController|AbstractController|ActiveSupport)::/)).to be_empty
    expect(concerns).to eq([])
  end

  it "raises not_action_controller for a model constant" do
    lib_path = File.expand_path("../../../lib", __dir__)
    stdout, stderr, status = run_in_fixture_app(<<~RUBY)
      $LOAD_PATH.unshift(#{lib_path.inspect})
      require "coatepec"
      Coatepec::Worker::RailsRuntime.new(#{FIXTURE_APP_ROOT.inspect}).boot!
      begin
        Coatepec::Introspection::Controller.new("Widget").call
        puts JSON.generate(error: nil)
      rescue Coatepec::Error => e
        puts JSON.generate(error: e.code.to_s)
      end
    RUBY

    expect(status).to be_success, stderr
    result = JSON.parse(stdout.lines.last)
    expect(result["error"]).to eq("not_action_controller")
  end
end
