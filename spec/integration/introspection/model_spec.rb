# frozen_string_literal: true

require "spec_helper"

RSpec.describe Coatepec::Introspection::Model, type: :integration do
  def run_model_call(ruby_tail)
    lib_path = File.expand_path("../../../lib", __dir__)
    run_in_fixture_app(<<~RUBY)
      $LOAD_PATH.unshift(#{lib_path.inspect})
      require "coatepec"
      Coatepec::Worker::RailsRuntime.new(#{FIXTURE_APP_ROOT.inspect}).boot!
      #{ruby_tail}
    RUBY
  end

  it "returns Widget's real columns, association, and validator" do
    stdout, stderr, status = run_model_call(<<~RUBY)
      result = Coatepec::Introspection::Model.new("Widget").call
      puts JSON.generate(result)
    RUBY

    expect(status).to be_success, stderr
    result = JSON.parse(stdout.lines.last)

    expect(result["name"]).to eq("Widget")
    expect(result["columns"].map { |c| c["name"] }).to include("name", "sku", "active", "owner_id")
    owner_assoc = result["associations"].find { |a| a["name"] == "owner" }
    expect(owner_assoc["macro"]).to eq("belongs_to")
    expect(owner_assoc["class_name"]).to eq("Owner")
    name_validator = result["validators"].find { |v| v["attributes"] == ["name"] }
    expect(name_validator).not_to be_nil
  end

  it "raises not_active_record_model for a real, non-AR project constant" do
    stdout, stderr, status = run_model_call(<<~RUBY)
      begin
        Coatepec::Introspection::Model.new("ApplicationController").call
        puts JSON.generate(error: nil)
      rescue Coatepec::Error => e
        puts JSON.generate(error: e.code.to_s)
      end
    RUBY

    expect(status).to be_success, stderr
    result = JSON.parse(stdout.lines.last)

    expect(result["error"]).to eq("not_active_record_model")
  end

  it "raises model_not_found for a well-formed but nonexistent constant" do
    stdout, stderr, status = run_model_call(<<~RUBY)
      begin
        Coatepec::Introspection::Model.new("NoSuchModel").call
        puts JSON.generate(error: nil)
      rescue Coatepec::Error => e
        puts JSON.generate(error: e.code.to_s)
      end
    RUBY

    expect(status).to be_success, stderr
    result = JSON.parse(stdout.lines.last)

    expect(result["error"]).to eq("model_not_found")
  end
end
