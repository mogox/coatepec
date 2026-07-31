# frozen_string_literal: true

module Coatepec
  module Spec
    # Opt-in macOS fork strategy: attempts Process.fork like ForkStrategy
    # (reusing the warm worker's boot), but only after two cheap guard
    # checks pass, and transparently falls back to a fresh SpawnStrategy
    # run -- for this call only -- when a guard fails or the forked child
    # crashes. See docs/superpowers/specs/2026-07-31-macos-guarded-fork-design.md.
    class GuardedForkStrategy < ForkStrategy
      # Intentionally empty at ship time: the one documented crash this
      # guards against didn't name a specific culprit gem, just "something
      # ObjC-initializing on another thread." This is an extension point
      # for real incidents (refine via a project's own .coatepec.yml
      # macos_fork_unsafe_gems), not a researched-and-complete list.
      BUILTIN_UNSAFE_GEMS = [].freeze

      # Live thread count is allowed to exceed the post-boot baseline by
      # this much before the guard treats it as "something is mid-init."
      THREAD_COUNT_TOLERANCE = 1

      CRASH_SIGNAL_NAMES = %w[ABRT SEGV BUS].freeze

      # A crash retry shares one timeout budget with the fork attempt that
      # preceded it: WorkerManager only gives the whole dispatch
      # timeout_seconds + 10 before Client#read_response raises
      # DisconnectedError and the warm worker is restarted from scratch --
      # exactly the boot this feature exists to preserve. The floor keeps a
      # nearly-exhausted budget from turning the retry into a guaranteed
      # timeout kill; a few seconds is enough for a fast spec to still land.
      MIN_RETRY_TIMEOUT_SECONDS = 5

      # The crashed child's stderr carries the macOS crash report -- the only
      # evidence that could ever populate BUILTIN_UNSAFE_GEMS from a real
      # incident. Kept far below Result::MAX_OUTPUT_BYTES because it rides
      # along with a whole second result inside MCP::Response's 1 MiB cap.
      MAX_CRASH_STDERR_BYTES = 4 * 1024

      def initialize(project_root, project: nil, rails_runtime: nil)
        super
        @spawn_strategy = SpawnStrategy.new(project_root)
      end

      def run(args, timeout_seconds)
        return fallback_result(args, timeout_seconds, "spawn_fallback") unless guard_passes?

        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        begin
          result = super
        rescue SystemCallError
          # Process.fork itself failed (Errno::EAGAIN/ENOMEM under
          # process-table pressure), so no child was ever produced -- from the
          # caller's side that is indistinguishable from a failed guard, hence
          # the same mode. Opting into macos_fork must never surface an error
          # that plain SpawnStrategy wouldn't have.
          return fallback_result(args, timeout_seconds, "spawn_fallback")
        end
        return result.merge(execution_mode: "fork") unless crashed?(result)

        retry_after_crash(args, timeout_seconds, started_at, result)
      end

      private

      def retry_after_crash(args, timeout_seconds, started_at, crashed)
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
        remaining = [timeout_seconds - elapsed, MIN_RETRY_TIMEOUT_SECONDS].max

        fallback_result(args, remaining, "spawn_after_crash")
          .merge(crashed_fork_stderr: crash_diagnostics(crashed))
      end

      # Keeps the tail, matching Result#read_bounded: a crash report's tail is
      # where the signal and backtrace land.
      def crash_diagnostics(result)
        text = result[:stderr].to_s
        return text unless text.bytesize > MAX_CRASH_STDERR_BYTES

        text.byteslice(-MAX_CRASH_STDERR_BYTES, MAX_CRASH_STDERR_BYTES)
      end

      def fallback_result(args, timeout_seconds, mode)
        @spawn_strategy.run(args, timeout_seconds).merge(execution_mode: mode)
      end

      def guard_passes?
        thread_count_ok? && !unsafe_gems_loaded?
      end

      def thread_count_ok?
        baseline = @rails_runtime&.post_boot_thread_count
        return true unless baseline

        Thread.list.count <= baseline + THREAD_COUNT_TOLERANCE
      end

      def unsafe_gems_loaded?
        denylist = BUILTIN_UNSAFE_GEMS + configured_unsafe_gems
        return false if denylist.empty?

        loaded = @rails_runtime&.loaded_gem_names || []
        !(denylist & loaded).empty?
      end

      def configured_unsafe_gems
        @project&.config&.macos_fork_unsafe_gems || []
      end

      def crashed?(result)
        return false unless result[:signaled]

        CRASH_SIGNAL_NAMES.any? { |name| Signal.list[name] == result[:termsig] }
      end
    end
  end
end
