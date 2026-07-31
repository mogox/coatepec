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

      def initialize(project_root, project: nil, rails_runtime: nil)
        super
        @spawn_strategy = SpawnStrategy.new(project_root)
      end

      def run(args, timeout_seconds)
        return fallback_result(args, timeout_seconds, "spawn_fallback") unless guard_passes?

        result = super
        return result.merge(execution_mode: "fork") unless crashed?(result)

        fallback_result(args, timeout_seconds, "spawn_after_crash")
      end

      private

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
