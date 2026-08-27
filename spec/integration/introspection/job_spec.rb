# frozen_string_literal: true

require "spec_helper"

RSpec.describe Coatepec::Introspection::Job, type: :integration do
  def run_job_call(ruby_tail)
    lib_path = File.expand_path("../../../lib", __dir__)
    run_in_fixture_app(<<~RUBY)
      $LOAD_PATH.unshift(#{lib_path.inspect})
      require "coatepec"
      Coatepec::Worker::RailsRuntime.new(#{FIXTURE_APP_ROOT.inspect}).boot!
      #{ruby_tail}
    RUBY
  end

  it "returns WidgetIndexJob's real queue name, priority, callbacks, and rescued exceptions" do
    stdout, stderr, status = run_job_call(<<~RUBY)
      result = Coatepec::Introspection::Job.new("WidgetIndexJob").call
      puts JSON.generate(result)
    RUBY

    expect(status).to be_success, stderr
    result = JSON.parse(stdout.lines.last)

    expect(result["name"]).to eq("WidgetIndexJob")
    expect(result["queue_name"]).to eq("low_priority")
    expect(result["queue_priority"]).to be_nil

    before_callback = result["callbacks"].find { |c| c["kind"] == "before" }
    expect(before_callback["filter"]).to eq("log_start")
    around_callback = result["callbacks"].find { |c| c["kind"] == "around" }
    expect(around_callback["filter"]).to eq("(block)")

    expect(result["rescued_exceptions"]).to include("Net::OpenTimeout", "ActiveJob::DeserializationError")
  end

  it "returns a plain default queue name for a job that never calls queue_as" do
    stdout, stderr, status = run_job_call(<<~RUBY)
      class PlainJob < ApplicationJob
        def perform; end
      end

      result = Coatepec::Introspection::Job.new("PlainJob").call
      # ApplicationJob itself is the baseline to diff against below, rather
      # than a hardcoded empty array: on Rails 7.1, ActiveJob::Base includes
      # Timezones/Translation concerns that each register a framework-level
      # around_perform callback (wrapping perform in Time.use_zone/
      # I18n.with_locale) -- machinery Rails 8.1 no longer has. Every job
      # inherits those on 7.1, so "no callbacks at all" isn't a
      # version-stable assertion; "no callbacks beyond what ApplicationJob
      # itself already carries" is.
      base = Coatepec::Introspection::Job.new("ApplicationJob").call
      puts JSON.generate(plain: result, base: base)
    RUBY

    expect(status).to be_success, stderr
    parsed = JSON.parse(stdout.lines.last)
    result = parsed["plain"]
    base = parsed["base"]

    # Regression guard for the class-level-vs-instance-level queue_name
    # landmine this plan documents: must be the string "default", never a
    # serialized/blank representation of the unevaluated default Proc.
    expect(result["queue_name"]).to eq("default")
    expect(result["callbacks"]).to eq(base["callbacks"])
    expect(result["rescued_exceptions"]).to eq(base["rescued_exceptions"])
  end

  it "raises not_active_job for a real, non-ActiveJob project constant" do
    stdout, stderr, status = run_job_call(<<~RUBY)
      begin
        Coatepec::Introspection::Job.new("Widget").call
        puts JSON.generate(error: nil)
      rescue Coatepec::Error => e
        puts JSON.generate(error: e.code.to_s)
      end
    RUBY

    expect(status).to be_success, stderr
    result = JSON.parse(stdout.lines.last)

    expect(result["error"]).to eq("not_active_job")
  end

  it "raises job_not_found for a well-formed but nonexistent constant" do
    stdout, stderr, status = run_job_call(<<~RUBY)
      begin
        Coatepec::Introspection::Job.new("NoSuchJob").call
        puts JSON.generate(error: nil)
      rescue Coatepec::Error => e
        puts JSON.generate(error: e.code.to_s)
      end
    RUBY

    expect(status).to be_success, stderr
    result = JSON.parse(stdout.lines.last)

    expect(result["error"]).to eq("job_not_found")
  end
end
