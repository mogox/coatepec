# frozen_string_literal: true

module Coatepec
  module Spec
    # Validates a `rails_spec_run` request's paths, builds the RSpec CLI
    # args, and delegates to the platform-appropriate process strategy
    # (fork on Linux, spawn elsewhere).
    class Runner
      DEFAULT_TIMEOUT = 120

      def initialize(project_root)
        @project_root = project_root
        @path_policy = PathPolicy.new(Project.new(project_root))
      end

      def run(paths:, example: nil, seed: nil, fail_fast: false, timeout_seconds: DEFAULT_TIMEOUT)
        require_rspec!
        selectors = @path_policy.validate!(paths)
        args = build_args(selectors, example, seed, fail_fast)

        strategy_class.new(@project_root).run(args, timeout_seconds)
      end

      private

      def strategy_class
        RbConfig::CONFIG["host_os"].match?(/linux/) ? ForkStrategy : SpawnStrategy
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
