# frozen_string_literal: true

require "securerandom"

module Coatepec
  module Worker
    class RailsRuntime
      attr_reader :pid, :boot_id, :boot_duration_ms, :ruby_version, :rails_version

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
        require File.join(@project_root, "config/environment")

        @pid = Process.pid
        @boot_id = SecureRandom.hex(8)
        @ruby_version = RUBY_VERSION
        @rails_version = Rails.version
        @boot_duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
        @booted = true
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
    end
  end
end
