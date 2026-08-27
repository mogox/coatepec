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

    update = result["actions"].find { |a| a["name"] == "update" }
    expect(update["routes"].map { |r| r["verb"] }).to contain_exactly("PATCH", "PUT")

    expect(result["unroutable_actions"]).to include("orphaned")
    expect(result["routes_without_action"]).to eq(["removed_long_ago"])
  end

  it "handles a namespaced controller's controller_path and routes" do
    result = result_for("Admin::ReportsController")

    expect(result["controller_path"]).to eq("admin/reports")
    index = result["actions"].find { |a| a["name"] == "index" }
    expect(index["routes"].first["path"]).to eq("/admin/reports(.:format)")
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
