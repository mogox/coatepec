# frozen_string_literal: true

module Coatepec
  module Spec
    # The RSpec half of the framework adapter contract the process
    # strategies run against: CLI args, the JSON formatter wiring, the
    # in-process call a forked child makes, and the spawn command line.
    # Every method here is a verbatim extraction of what Runner/
    # ProcessStrategy/ForkStrategy/SpawnStrategy did inline before
    # TestUnit::Adapter needed the same seams.
    class RSpecAdapter
      def initialize(project_root)
        @project_root = project_root
      end

      def framework
        :rspec
      end

      def require_framework!
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

      def json_args(json_path)
        ["--format", "progress", "--format", "json", "--out", json_path]
      end

      # Runs inside the forked child. RSpec freezes its own "load started
      # at" timestamp once, at the moment rspec/core.rb is first required --
      # in this architecture, that's when the long-lived warm worker booted,
      # not when THIS run started. Every forked child inherits that frozen
      # timestamp via copy-on-write, so RSpec's own "(files took N seconds
      # to load)" reporting would otherwise measure "time since the worker
      # booted" and grow across every run for as long as the worker stays
      # warm. Reset it fresh before each run.
      def run_in_process(full_args, _json_path)
        RSpec.configuration.start_time = RSpec::Core::Time.now

        RSpec::Core::Runner.run(full_args, $stderr, $stdout)
      end

      def spawn_command(full_args, _json_path)
        [{ "RAILS_ENV" => "test" }, ["bundle", "exec", "rspec", *full_args]]
      end
    end
  end
end
