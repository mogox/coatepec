# frozen_string_literal: true

module Coatepec
  module Spec
    # Validates a `rails_spec_run` request's paths, builds the RSpec CLI
    # args, and delegates to the platform-appropriate process strategy
    # (fork on Linux, spawn on macOS, or a guarded fork on macOS when the
    # project opts in via .coatepec.yml).
    class Runner
      DEFAULT_TIMEOUT = 120

      def initialize(project_root, rails_runtime: nil)
        @project_root = project_root
        @project = Project.new(project_root)
        @path_policy = PathPolicy.new(@project)
        @rails_runtime = rails_runtime
      end

      def run(paths:, example: nil, seed: nil, fail_fast: false, timeout_seconds: DEFAULT_TIMEOUT)
        require_rspec!
        selectors = @path_policy.validate!(paths)
        args = build_args(selectors, example, seed, fail_fast)

        strategy_class.new(@project_root, project: @project, rails_runtime: @rails_runtime).run(args, timeout_seconds)
      end

      private

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

      def require_rspec!
        require "rspec/core"
      rescue LoadError
        raise Coatepec::Error.new(:unsupported_test_framework, "rspec-rails must be in the application's test group")
      end

      def build_args(selectors, example, seed, fail_fast)
        args = selectors.dup
        args += ["-e", example] if example
        args += ["--seed", seed.to_s] if seed
        args << "--fail-fast" if fail_fast

        args
      end
    end
  end
end
