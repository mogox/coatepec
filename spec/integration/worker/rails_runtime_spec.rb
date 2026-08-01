# frozen_string_literal: true

require "spec_helper"

RSpec.describe Coatepec::Worker::RailsRuntime, type: :integration do
  it "boots the fixture app in test env and reports status" do
    lib_path = File.expand_path("../../../lib", __dir__)
    stdout, stderr, status = run_in_fixture_app(<<~RUBY)
      $LOAD_PATH.unshift(#{lib_path.inspect})
      require "coatepec"
      runtime = Coatepec::Worker::RailsRuntime.new(#{FIXTURE_APP_ROOT.inspect})
      runtime.boot!
      puts JSON.generate(runtime.status)
    RUBY

    expect(status).to be_success, stderr
    result = JSON.parse(stdout.lines.last)

    expect(result["rails_version"]).to match(/\A(7\.1|8\.1)\./)
    expect(result["environment"]).to eq("test")
    expect(result["pid"]).to be_a(Integer)
    expect(result["boot_id"]).to be_a(String)
    expect(result["boot_duration_ms"]).to be >= 0
    expect(result["lifecycle_state"]).to eq("ready")
  end

  it "records the post-boot thread count and loaded gem names" do
    lib_path = File.expand_path("../../../lib", __dir__)
    stdout, stderr, status = run_in_fixture_app(<<~RUBY)
      $LOAD_PATH.unshift(#{lib_path.inspect})
      require "coatepec"
      runtime = Coatepec::Worker::RailsRuntime.new(#{FIXTURE_APP_ROOT.inspect})
      runtime.boot!
      puts JSON.generate(
        post_boot_thread_count: runtime.post_boot_thread_count,
        loaded_gem_names: runtime.loaded_gem_names
      )
    RUBY

    expect(status).to be_success, stderr
    result = JSON.parse(stdout.lines.last)

    expect(result["post_boot_thread_count"]).to be > 0
    expect(result["loaded_gem_names"]).to include("rails")
  end

  it "raises worker_failure when config/environment.rb does not exist" do
    runtime = described_class.new("/nonexistent/project")

    expect { runtime.boot! }.to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:worker_failure) }
  end

  it "boots with a real, migrated Widget/Owner fixture model available" do
    lib_path = File.expand_path("../../../lib", __dir__)
    stdout, stderr, status = run_in_fixture_app(<<~RUBY)
      $LOAD_PATH.unshift(#{lib_path.inspect})
      require "coatepec"
      Coatepec::Worker::RailsRuntime.new(#{FIXTURE_APP_ROOT.inspect}).boot!
      puts JSON.generate(
        widget_columns: Widget.column_names.sort,
        widget_belongs_to_owner: Widget.reflect_on_association(:owner).macro.to_s,
        owner_has_many_widgets: Owner.reflect_on_association(:widgets).macro.to_s
      )
    RUBY

    expect(status).to be_success, stderr
    result = JSON.parse(stdout.lines.last)

    expect(result["widget_columns"]).to include("name", "sku", "active", "owner_id")
    expect(result["widget_belongs_to_owner"]).to eq("belongs_to")
    expect(result["owner_has_many_widgets"]).to eq("has_many")
  end

  it "picks up an edited model's Ruby-defined metadata without a worker restart" do
    lib_path = File.expand_path("../../../lib", __dir__)
    widget_path = File.join(FIXTURE_APP_ROOT, "app/models/widget.rb")
    original = File.read(widget_path)

    stdout, stderr, status = run_in_fixture_app(<<~RUBY)
      $LOAD_PATH.unshift(#{lib_path.inspect})
      require "coatepec"
      Coatepec::Worker::RailsRuntime.new(#{FIXTURE_APP_ROOT.inspect}).boot!

      before_validators = Widget.validators.map { |v| v.class.name }.sort

      File.write(#{widget_path.inspect}, File.read(#{widget_path.inspect}).sub(
        "validates :name, presence: true",
        "validates :name, presence: true\n  validates :sku, presence: true"
      ))
      sleep 1 # file mtime resolution on some filesystems is 1-second granular

      Rails.application.reloader.wrap {}

      after_validators = Object.const_get(:Widget).validators.map { |v| v.class.name }.sort
      puts JSON.generate(before: before_validators, after: after_validators)
    RUBY

    File.write(widget_path, original)

    expect(status).to be_success, stderr
    result = JSON.parse(stdout.lines.last)

    # Widget already carries 2 validators before any edit: the explicit
    # `validates :name, presence: true` plus the presence validator Rails
    # auto-adds for `belongs_to :owner` under `config.load_defaults` (true by
    # default since Rails 5). The edit below adds a third, on :sku.
    expect(result["before"].size).to eq(2)
    expect(result["after"].size).to eq(3)
  end
end
