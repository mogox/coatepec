# frozen_string_literal: true

require "spec_helper"

RSpec.describe Coatepec::Worker::RailsRuntime, type: :integration do
  # Several examples below rewrite a *committed* fixture file (a model, the
  # app's config/environments/test.rb) for the duration of one example. The
  # restore has to be unconditional: a failed assertion, a raising subprocess
  # call, or a Ctrl-C between the edit and the restore must not leave the
  # fixture app mutated -- silently misconfigured relative to git -- on disk.
  def with_restored_file(path)
    original = File.read(path)
    yield original
  ensure
    File.write(path, original) if original
  end

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

    with_restored_file(widget_path) do
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

      expect(status).to be_success, stderr
      result = JSON.parse(stdout.lines.last)

      # Widget already carries 2 validators before any edit: the explicit
      # `validates :name, presence: true` plus the presence validator Rails
      # auto-adds for `belongs_to :owner` under `config.load_defaults` (true by
      # default since Rails 5). The edit above adds a third, on :sku.
      expect(result["before"].size).to eq(2)
      expect(result["after"].size).to eq(3)
    end
  end

  it "forces reloading on even when the target app uses the legacy config.cache_classes= form" do
    lib_path = File.expand_path("../../../lib", __dir__)
    widget_path = File.join(FIXTURE_APP_ROOT, "app/models/widget.rb")
    test_env_path = File.join(FIXTURE_APP_ROOT, "config/environments/test.rb")

    with_restored_file(widget_path) do
      with_restored_file(test_env_path) do |original_test_env|
        # Rewrite to the legacy form the modern `enable_reloading=` override
        # doesn't intercept: `cache_classes` remains a plain attr_accessor in
        # both Rails 7.1 and 8.1, so a target app writing it directly bypasses
        # `enable_reloading=` entirely unless `cache_classes=` is also covered.
        legacy_test_env = original_test_env.sub(
          "config.enable_reloading = false",
          "config.cache_classes = true"
        )
        if legacy_test_env == original_test_env
          raise "fixture's test.rb no longer matches the expected enable_reloading= line"
        end

        File.write(test_env_path, legacy_test_env)

        stdout, stderr, status = run_in_fixture_app(<<~RUBY)
          $LOAD_PATH.unshift(#{lib_path.inspect})
          require "coatepec"
          Coatepec::Worker::RailsRuntime.new(#{FIXTURE_APP_ROOT.inspect}).boot!

          before_validators = Widget.validators.map { |v| v.class.name }.sort

          File.write(#{widget_path.inspect}, File.read(#{widget_path.inspect}).sub(
            "validates :name, presence: true",
            "validates :name, presence: true\\n  validates :sku, presence: true"
          ))
          sleep 1 # file mtime resolution on some filesystems is 1-second granular

          Rails.application.reloader.wrap {}

          after_validators = Object.const_get(:Widget).validators.map { |v| v.class.name }.sort
          puts JSON.generate(
            cache_classes: Rails.application.config.cache_classes,
            enable_reloading: Rails.application.config.enable_reloading,
            before: before_validators,
            after: after_validators
          )
        RUBY

        expect(status).to be_success, stderr
        result = JSON.parse(stdout.lines.last)

        expect(result["cache_classes"]).to eq(false)
        expect(result["enable_reloading"]).to eq(true)
        expect(result["before"].size).to eq(2)
        expect(result["after"].size).to eq(3)
      end
    end
  end

  it "forces the polling file watcher even when the target app configures an evented one" do
    lib_path = File.expand_path("../../../lib", __dir__)
    test_env_path = File.join(FIXTURE_APP_ROOT, "config/environments/test.rb")

    with_restored_file(test_env_path) do |original_test_env|
      # A stand-in for ActiveSupport::EventedFileUpdateChecker: merely
      # *naming* the real constant would load active_support/
      # evented_file_update_checker.rb, whose first line is `gem "listen"` --
      # a gem deliberately absent from the fixture app's bundle. The override
      # under test is value-blind, so any assigned class exercises it; what
      # matters is that the app's own assignment does not survive boot.
      watcher_test_env = original_test_env.sub(
        "Rails.application.configure do",
        "class CoatepecFakeEventedWatcher; end\n\nRails.application.configure do\n" \
        "  config.file_watcher = CoatepecFakeEventedWatcher"
      )
      raise "fixture's test.rb no longer matches the expected configure block" if watcher_test_env == original_test_env

      File.write(test_env_path, watcher_test_env)

      stdout, stderr, status = run_in_fixture_app(<<~RUBY)
        $LOAD_PATH.unshift(#{lib_path.inspect})
        require "coatepec"
        Coatepec::Worker::RailsRuntime.new(#{FIXTURE_APP_ROOT.inspect}).boot!
        puts JSON.generate(file_watcher: Rails.application.config.file_watcher.name)
      RUBY

      expect(status).to be_success, stderr
      result = JSON.parse(stdout.lines.last)

      expect(result["file_watcher"]).to eq("ActiveSupport::FileUpdateChecker")
    end
  end
end
