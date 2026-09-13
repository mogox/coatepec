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

  it "reports next_offset while pages remain and nil on the last one" do
    lib_path = File.expand_path("../../../lib", __dir__)
    stdout, stderr, status = run_in_fixture_app(<<~RUBY)
      $LOAD_PATH.unshift(#{lib_path.inspect})
      require "coatepec"
      Coatepec::Worker::RailsRuntime.new(#{FIXTURE_APP_ROOT.inspect}).boot!
      puts JSON.generate(Coatepec::Introspection::Routes.new(query: "audits", limit: 1).call)
      puts JSON.generate(Coatepec::Introspection::Routes.new(query: "audits", limit: 1, offset: 1).call)
    RUBY

    expect(status).to be_success, stderr
    first, last = stdout.lines.last(2).map { |line| JSON.parse(line) }

    expect(first["items"].size).to eq(1)
    expect(first["next_offset"]).to eq(1)
    expect(last["next_offset"]).to be_nil
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

  it "drops engine routes under engines: exclude and keeps only them under engines: only" do
    lib_path = File.expand_path("../../../lib", __dir__)
    stdout, stderr, status = run_in_fixture_app(<<~RUBY)
      $LOAD_PATH.unshift(#{lib_path.inspect})
      require "coatepec"
      Coatepec::Worker::RailsRuntime.new(#{FIXTURE_APP_ROOT.inspect}).boot!
      puts JSON.generate(Coatepec::Introspection::Routes.new(engines: "exclude", limit: 200).call)
      puts JSON.generate(Coatepec::Introspection::Routes.new(engines: "only", limit: 200).call)
    RUBY

    expect(status).to be_success, stderr
    excluded, only = stdout.lines.last(2).map { |line| JSON.parse(line) }

    expect(excluded["items"].map { |r| r["engine"] }).to all(be_nil)
    expect(excluded["items"].map { |r| r["name"] }).to include("widgets", "widget_admin")
    expect(only["items"].map { |r| r["engine"] }).to all(eq("WidgetAdmin::Engine"))
    expect(only["items"]).not_to be_empty
    expect(excluded["matched"] + only["matched"]).to eq(excluded["items"].size + only["items"].size)
  end
end
