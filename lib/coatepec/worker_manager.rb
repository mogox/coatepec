# frozen_string_literal: true

require "monitor"

module Coatepec
  class WorkerManager
    def initialize(project)
      @project = project
      @change_detector = Worker::ChangeDetector.new(project.root)
      @client = nil
      @snapshot = nil
      @lock = Monitor.new
    end

    def status
      dispatch("status", {}, timeout: 30)
    end

    def run_spec(paths:, example:, seed:, fail_fast:, timeout_seconds:)
      dispatch(
        "spec_run",
        { paths: paths, example: example, seed: seed, fail_fast: fail_fast, timeout_seconds: timeout_seconds },
        timeout: timeout_seconds + 10
      )
    end

    def stop
      @lock.synchronize { @client&.stop }
    end

    private

    def dispatch(command, args, timeout:, retried: false)
      @lock.synchronize do
        ensure_worker!
        check_for_restart!

        begin
          @client.request(command, args, timeout: timeout)
        rescue Worker::Client::DisconnectedError
          raise Coatepec::Error.new(:worker_disconnected, "Worker disconnected") if retried

          restart_worker!
          dispatch(command, args, timeout: timeout, retried: true)
        end
      end
    end

    def check_for_restart!
      reason = @change_detector.restart_reason(@snapshot)
      case reason
      when :sidecar_restart_required
        raise Coatepec::Error.new(:sidecar_restart_required, "Gemfile changed; restart Coatepec")
      when :worker_restart_required
        restart_worker!
      end
    end

    def ensure_worker!
      restart_worker! unless @client&.alive?
    end

    def restart_worker!
      @client&.stop
      @client = Worker::Client.spawn(@project.root)
      @snapshot = @change_detector.snapshot
    end
  end
end
