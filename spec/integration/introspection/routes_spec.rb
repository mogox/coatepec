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
end
