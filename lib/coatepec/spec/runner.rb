# frozen_string_literal: true

module Coatepec
  module Spec
    # Validates a `rails_spec_run` request's paths, picks the RSpec or
    # Minitest adapter from their shape, builds the CLI args, and delegates
    # to the platform-appropriate process strategy (fork on Linux, and a
    # guarded fork on macOS unless the project opts out via .coatepec.yml,
    # which selects a fresh spawn per call).
    class Runner
      DEFAULT_TIMEOUT = 120

      def initialize(project_root, rails_runtime: nil)
        @project_root = project_root
        @project = Project.new(project_root)
        @path_policy = PathPolicy.new(@project)
        @rails_runtime = rails_runtime
      end

      def run(paths:, example: nil, seed: nil, fail_fast: false, timeout_seconds: DEFAULT_TIMEOUT,
              include_passing: false, include_stdout: "failures")
        validated = @path_policy.validate!(paths)
        adapter = adapter_for(validated[:framework])
        adapter.require_framework!
        args = adapter.build_args(validated[:selectors], example, seed, fail_fast)

        result = strategy_class
                 .new(@project_root, adapter: adapter, project: @project, rails_runtime: @rails_runtime)
                 .run(args, timeout_seconds, include_passing: include_passing, include_stdout: include_stdout)
        @rails_runtime&.record_execution_mode(result[:execution_mode])
        result
      end

      # Reported by rails_runtime_status so a caller can see which path a run will take.
      def strategy_name
        { ForkStrategy => "fork", GuardedForkStrategy => "guarded_fork", SpawnStrategy => "spawn" }
          .fetch(strategy_class)
      end

      private

      # Selector shape decides the framework (see PathPolicy); the adapter
      # decides everything framework-specific after that.
      def adapter_for(framework)
        case framework
        when :minitest then TestUnit::Adapter.new(@project_root)
        else RSpecAdapter.new(@project_root)
        end
      end

      def strategy_class
        case RbConfig::CONFIG["host_os"]
        when /linux/ then ForkStrategy
        # The macos_fork config key governs this whole branch, BSD included --
        # the name tracks the documented macOS incident, not the platform set.
        when /darwin|bsd/ then macos_strategy_class
        else raise Coatepec::Error.new(:unsupported_platform, "Coatepec supports macOS and Linux only")
        end
      end

      # Forking is the default; only an explicit `macos_fork: false` spawns. Only the macOS
      # branch reads the file here; the MCP layer reads it on every call for `defaults`.
      def macos_strategy_class
        @project.config.macos_fork? ? GuardedForkStrategy : SpawnStrategy
      end
    end
  end
end
