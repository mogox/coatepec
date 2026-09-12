# frozen_string_literal: true

module Coatepec
  module Spec
    # Validates a `rails_spec_run` request's paths, picks the RSpec or
    # Minitest adapter from their shape, builds the CLI args, and delegates
    # to the platform-appropriate process strategy (fork on Linux, spawn on
    # macOS, or a guarded fork on macOS when the project opts in via
    # .coatepec.yml).
    class Runner
      DEFAULT_TIMEOUT = 120

      def initialize(project_root, rails_runtime: nil)
        @project_root = project_root
        @project = Project.new(project_root)
        @path_policy = PathPolicy.new(@project)
        @rails_runtime = rails_runtime
      end

      def run(paths:, example: nil, seed: nil, fail_fast: false, timeout_seconds: DEFAULT_TIMEOUT,
              include_passing: false)
        validated = @path_policy.validate!(paths)
        adapter = adapter_for(validated[:framework])
        adapter.require_framework!
        args = adapter.build_args(validated[:selectors], example, seed, fail_fast)

        strategy_class.new(@project_root, adapter: adapter, project: @project, rails_runtime: @rails_runtime)
                      .run(args, timeout_seconds, include_passing: include_passing)
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

      # Reading @project.config here means an invalid .coatepec.yml only
      # raises :invalid_config on macOS -- the Linux branch never touches it.
      # Accepted asymmetry: the file exists to configure this branch.
      def macos_strategy_class
        @project.config.macos_fork? ? GuardedForkStrategy : SpawnStrategy
      end
    end
  end
end
