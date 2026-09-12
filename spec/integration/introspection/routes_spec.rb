# frozen_string_literal: true

require "spec_helper"

RSpec.describe Coatepec::Introspection::Routes, type: :integration do
  it "lists the real fixture app's widgets route" do
    lib_path = File.expand_path("../../../lib", __dir__)
    stdout, stderr, status = run_in_fixture_app(<<~RUBY)
      $LOAD_PATH.unshift(#{lib_path.inspect})
      require "coatepec"
      Coatepec::Worker::RailsRuntime.new(#{FIXTURE_APP_ROOT.inspect}).boot!
      result = Coatepec::Introspection::Routes.new(query: "widgets").call
      puts JSON.generate(result)
    RUBY

    expect(status).to be_success, stderr
    result = JSON.parse(stdout.lines.last)

    widget_index = result["items"].find { |r| r["controller"] == "widgets" && r["action"] == "index" }
    expect(widget_index).not_to be_nil
    expect(widget_index["verb"]).to eq("GET")
  end

  it "lists the routes of the mounted WidgetAdmin engine with their mount prefix" do
    lib_path = File.expand_path("../../../lib", __dir__)
    stdout, stderr, status = run_in_fixture_app(<<~RUBY)
      $LOAD_PATH.unshift(#{lib_path.inspect})
      require "coatepec"
      Coatepec::Worker::RailsRuntime.new(#{FIXTURE_APP_ROOT.inspect}).boot!
      result = Coatepec::Introspection::Routes.new(query: "audits").call
      puts JSON.generate(result)
    RUBY

    expect(status).to be_success, stderr
    result = JSON.parse(stdout.lines.last)

    index = result["items"].find { |r| r["controller"] == "widget_admin/audits" && r["action"] == "index" }
    expect(index).to include(
      "name" => "audits", "verb" => "GET", "path" => "/widget_admin/audits(.:format)",
      "engine" => "WidgetAdmin::Engine"
    )
    show = result["items"].find { |r| r["controller"] == "widget_admin/audits" && r["action"] == "show" }
    expect(show["path"]).to eq("/widget_admin/audits/:id(.:format)")
  end

  it "reports the engine mount as an application route and lists engine routes last" do
    lib_path = File.expand_path("../../../lib", __dir__)
    stdout, stderr, status = run_in_fixture_app(<<~RUBY)
      $LOAD_PATH.unshift(#{lib_path.inspect})
      require "coatepec"
      Coatepec::Worker::RailsRuntime.new(#{FIXTURE_APP_ROOT.inspect}).boot!
      result = Coatepec::Introspection::Routes.new(limit: 200).call
      puts JSON.generate(result)
    RUBY

    expect(status).to be_success, stderr
    items = JSON.parse(stdout.lines.last)["items"]

    # Every engine route is appended after the last application route, so once
    # the first engine-tagged item appears nothing untagged may follow it.
    first_engine = items.index { |r| r["engine"] }
    expect(first_engine).not_to be_nil
    expect(items[first_engine..].map { |r| r["engine"] }).to all(eq("WidgetAdmin::Engine"))
    expect(items.find { |r| r["controller"] == "widgets" && r["action"] == "index" }["engine"]).to be_nil
    expect(items.find { |r| r["name"] == "widget_admin" }).to include("engine" => nil)
  end
end
