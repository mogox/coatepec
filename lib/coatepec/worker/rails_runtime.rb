# frozen_string_literal: true

require "securerandom"

module Coatepec
  module Worker
    # Boots the fixture/target Rails app under RAILS_ENV=test exactly once
    # per worker process and reports its identity (pid, boot_id, versions,
    # lifecycle state) for rails_runtime_status.
    class RailsRuntime
      attr_reader :pid, :boot_id, :boot_duration_ms, :ruby_version, :rails_version, :post_boot_thread_count

      def initialize(project_root)
        @project_root = project_root
        @booted = false
      end

      def booted?
        @booted
      end

      def boot!
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        ENV["RAILS_ENV"] = "test"
        force_reloading!
        require File.join(@project_root, "config/environment")
        record_boot!(started_at)
      rescue Coatepec::Error
        raise
      rescue StandardError, LoadError => e
        raise Coatepec::Error.new(:worker_failure, "Rails failed to boot: #{e.message}")
      end

      def status
        {
          pid: pid,
          boot_id: boot_id,
          ruby_version: ruby_version,
          rails_version: rails_version,
          boot_duration_ms: boot_duration_ms,
          environment: "test",
          coatepec_version: Coatepec::VERSION,
          lifecycle_state: booted? ? "ready" : "not_started"
        }
      end

      # Loaded gem names for GuardedForkStrategy's denylist check. RailsRuntime
      # itself has no notion of macOS or forking -- it only exposes the raw
      # fact of what's loaded.
      def loaded_gem_names
        Gem.loaded_specs.keys.map(&:to_s)
      end

      private

      # Rails' test environment disables reloading by default, and Zeitwerk
      # refuses to enable reloading on a loader that's already had #setup
      # called on it -- which happens automatically, deep inside
      # Rails.application.initialize!, before any of our own code can run.
      # The only window to influence this is before the target app's own
      # config/environment.rb executes: intercept the config setter itself,
      # so whatever the app's test.rb assigns, reloading still ends up on.
      #
      # `require "bundler/setup"` here (before `require "rails"`) is
      # necessary, not optional: without it, `require "rails"` resolves
      # whatever Rails version RubyGems activates by default -- not
      # necessarily the one pinned by the target app's own Gemfile.lock --
      # and once the wrong version's gems are activated process-wide, the
      # target app's own later `require "bundler/setup"` (in its
      # config/boot.rb) raises a Gem::LoadError version conflict instead of
      # silently no-oping. BUNDLE_GEMFILE is already set to the target app's
      # Gemfile by the caller (Worker::Client's spawn env) before this
      # process starts, so this activates the correct version and the app's
      # own later Bundler.setup call is simply a no-op.
      def force_reloading!
        require "bundler/setup"
        require "rails"
        return if Rails::Application::Configuration.method_defined?(:coatepec_forces_reloading?)

        Rails::Application::Configuration.prepend(reload_forcing_module)
      end

      # `enable_reloading=` is overridden as the modern, documented setter.
      # `cache_classes=` is also overridden because Rails' own
      # `enable_reloading=` is implemented as `self.cache_classes = !value`
      # (see railties' application/configuration.rb) with `cache_classes`
      # remaining a plain attr_accessor underneath -- so a target app's
      # config/environments/test.rb using the legacy `config.cache_classes =
      # true` form would otherwise write that flag directly, bypassing the
      # `enable_reloading=` override entirely and silently leaving reloading
      # off.
      def reload_forcing_module
        Module.new do
          def coatepec_forces_reloading? = true

          def enable_reloading=(_value)
            super(true)
          end

          def cache_classes=(_value)
            super(false)
          end
        end
      end

      def record_boot!(started_at)
        @pid = Process.pid
        @boot_id = SecureRandom.hex(8)
        @ruby_version = RUBY_VERSION
        @rails_version = Rails.version
        @boot_duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
        @post_boot_thread_count = Thread.list.count
        @booted = true
      end
    end
  end
end
