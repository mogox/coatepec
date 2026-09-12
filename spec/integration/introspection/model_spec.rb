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
    # Must be a genuine `false`, not `nil` -- ActiveRecord::Base#abstract_class?
    # returns nil (not false) for concrete classes on Rails 7.1, but false on
    # Rails 8.1, so this has to be normalized in build_metadata.
    expect(result["abstract_class"]).to eq(false)
    expect(result["columns"].map { |c| c["name"] }).to include("name", "sku", "active", "owner_id")
    owner_assoc = result["associations"].find { |a| a["name"] == "owner" }
    expect(owner_assoc["macro"]).to eq("belongs_to")
    expect(owner_assoc["class_name"]).to eq("Owner")
    name_validator = result["validators"].find { |v| v["attributes"] == ["name"] }
    expect(name_validator).not_to be_nil
    status_enum = result["enums"].find { |e| e["name"] == "status" }
    expect(status_enum["values"]).to eq({ "draft" => 0, "published" => 1 })
  end

  it "keeps primitive validator options but drops non-primitive ones (e.g. Proc for if:)" do
    stdout, stderr, status = run_model_call(<<~RUBY)
      result = Coatepec::Introspection::Model.new("Owner").call
      puts JSON.generate(result)
    RUBY

    expect(status).to be_success, stderr
    result = JSON.parse(stdout.lines.last)

    # The validator class's exact namespace (ActiveModel:: vs. ActiveRecord::)
    # varies across Rails versions, so key off its options instead.
    length_validator = result["validators"].find { |v| v["attributes"] == ["name"] && v["options"].key?("minimum") }
    expect(length_validator).not_to be_nil
    # Plain-value options (Integer) survive.
    expect(length_validator["options"]["minimum"]).to eq(1)
    # The fixture declares `if: -> { true }` on this validator -- a Proc,
    # whose #to_s would otherwise leak this fixture app's absolute source
    # path and line number into the output. It must not appear at all.
    expect(length_validator["options"]).not_to have_key("if")
  end

  it "keeps a Symbol array option (e.g. `in:`) as an array of strings" do
    stdout, stderr, status = run_model_call(<<~RUBY)
      result = Coatepec::Introspection::Model.new("Owner").call
      puts JSON.generate(result)
    RUBY

    expect(status).to be_success, stderr
    result = JSON.parse(stdout.lines.last)

    # The fixture declares `validates :name, exclusion: { in: %i[admin root] }`.
    # A bare Symbol option value is already stringified, so a Symbol *array*
    # must be too -- otherwise the `in:` key vanishes entirely, which is what
    # `inclusion:`/`exclusion:`/`in:` looks like for most real Rails apps.
    in_validator = result["validators"].find { |v| v["options"].key?("in") }
    expect(in_validator).not_to be_nil
    expect(in_validator["options"]["in"]).to eq(%w[admin root])
  end

  it "collapses a validation declared by both a concern and the model body into one entry" do
    stdout, stderr, status = run_model_call(<<~RUBY)
      result = Coatepec::Introspection::Model.new("Owner").call
      puts JSON.generate(result)
    RUBY

    expect(status).to be_success, stderr
    result = JSON.parse(stdout.lines.last)

    # The fixture's Nameable concern and Owner's own body both declare
    # `validates :name, presence: true` -- two identical validator objects, one entry.
    presence_validators = result["validators"].select do |v|
      v["name"] == "ActiveRecord::Validations::PresenceValidator" && v["attributes"] == ["name"]
    end
    expect(presence_validators.size).to eq(1)
  end

  it "raises table_not_found for a concrete model whose table does not exist" do
    stdout, stderr, status = run_model_call(<<~RUBY)
      class GhostRecord < ActiveRecord::Base
        self.table_name = "does_not_exist"
      end

      begin
        Coatepec::Introspection::Model.new("GhostRecord").call
        puts JSON.generate(error: nil)
      rescue Coatepec::Error => e
        puts JSON.generate(error: e.code.to_s, message: e.message)
      end
    RUBY

    expect(status).to be_success, stderr
    result = JSON.parse(stdout.lines.last)

    expect(result["error"]).to eq("table_not_found")
    expect(result["message"]).to include("does_not_exist")
  end

  it "returns nil class_name for a real polymorphic belongs_to instead of crashing" do
    stdout, stderr, status = run_model_call(<<~RUBY)
      result = Coatepec::Introspection::Model.new("Note").call
      puts JSON.generate(result)
    RUBY

    expect(status).to be_success, stderr
    result = JSON.parse(stdout.lines.last)

    notable_assoc = result["associations"].find { |a| a["name"] == "notable" }
    expect(notable_assoc).not_to be_nil
    expect(notable_assoc["polymorphic"]).to eq(true)
    expect(notable_assoc["class_name"]).to be_nil
  end

  it "reports nil foreign_key/class_name for a has_one :through a polymorphic belongs_to instead of crashing" do
    stdout, stderr, status = run_model_call(<<~RUBY)
      result = Coatepec::Introspection::Model.new("Note").call
      puts JSON.generate(result)
    RUBY

    expect(status).to be_success, stderr
    result = JSON.parse(stdout.lines.last)

    # This is the field-level rescue (association_foreign_key) absorbing the
    # failure cleanly -- no "error" key, same as class_name's existing
    # polymorphic handling. The coarse safety net one layer up
    # (safe_association_data) is for failure modes neither field-level
    # rescue anticipates; it's covered at the unit level instead, since
    # provoking it here would mean relying on a *second*, still-undiscovered
    # ActiveRecord reflection quirk.
    notable_owner_assoc = result["associations"].find { |a| a["name"] == "notable_owner" }
    expect(notable_owner_assoc).not_to be_nil
    expect(notable_owner_assoc["class_name"]).to be_nil
    expect(notable_owner_assoc["foreign_key"]).to be_nil
    expect(notable_owner_assoc).not_to have_key("error")

    # The failure is scoped to notable_owner alone -- Note's other
    # association and the rest of its metadata come back intact.
    notable_assoc = result["associations"].find { |a| a["name"] == "notable" }
    expect(notable_assoc).not_to be_nil
    expect(notable_assoc).not_to have_key("error")
    expect(result["columns"].map { |c| c["name"] }).to include("id", "notable_type", "notable_id")
  end

  it "returns empty/nil table data for an abstract class instead of crashing" do
    stdout, stderr, status = run_model_call(<<~RUBY)
      result = Coatepec::Introspection::Model.new("ApplicationRecord").call
      puts JSON.generate(result)
    RUBY

    expect(status).to be_success, stderr
    result = JSON.parse(stdout.lines.last)

    expect(result["abstract_class"]).to eq(true)
    expect(result["table_name"]).to be_nil
    expect(result["primary_key"]).to be_nil
    expect(result["columns"]).to eq([])
    expect(result["associations"]).to eq([])
    expect(result["enums"]).to eq([])
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
