# frozen_string_literal: true

require "monitor"

module Coatepec
  # Owns the single warm Worker::Client for a project: lazily starts it,
  # restarts it when ChangeDetector flags a boot-file change, escalates a
  # Gemfile change to :sidecar_restart_required, and retries a request once
  # if the worker had died since the last dispatch.
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

    def routes(query: nil, limit: 50, offset: 0)
      dispatch("routes", { query: query, limit: limit, offset: offset }, timeout: 30)
    end

    def model(name:)
      dispatch("model", { name: name }, timeout: 30)
    end

    def stop
      @lock.synchronize { @client&.stop }
    end

    private

    def dispatch(command, args, timeout:, retried: false)
      @lock.synchronize do
        # The restart check must run against the *pre-existing* snapshot, before
        # ensure_worker! can re-baseline it by booting a fresh worker: a dead
        # worker plus a changed Gemfile must still surface
        # :sidecar_restart_required rather than silently adopting the new bundle.
        # There is nothing to compare against on the very first dispatch.
        check_for_restart! if @snapshot
        ensure_worker!
        perform(command, args, timeout: timeout, retried: retried)
      end
    end

    def perform(command, args, timeout:, retried:)
      @client.request(command, args, timeout: timeout)
    rescue Worker::Client::DisconnectedError
      raise Coatepec::Error.new(:worker_disconnected, "Worker disconnected") if retried

      restart_worker!
      dispatch(command, args, timeout: timeout, retried: true)
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
