# frozen_string_literal: true

module Coatepec
  module TestUnit
    # The Minitest half of the framework adapter contract (see
    # Spec::RSpecAdapter for the RSpec half and the method-by-method
    # contract). Everything Rails-/Minitest-specific about running a
    # `test/` selection lives here; the process strategies stay
    # framework-agnostic.
    #
    # The parent (warm worker) only ever calls require_framework!,
    # build_args, json_args and spawn_command. run_in_process runs in the
    # child -- a fork of the worker on Linux, or the fresh process
    # child_entry.rb starts on macOS -- and is the single place Minitest is
    # configured, so fork and spawn behave identically.
    class Adapter
      CHILD_ENTRY = File.expand_path("child_entry.rb", __dir__)
      JSON_PATH_ENV = "COATEPEC_MINITEST_JSON"

      def initialize(project_root)
        @project_root = project_root
      end

      def framework
        :minitest
      end

      # Only `minitest` itself here, never rails/test_help: that file runs
      # ActiveRecord::Migration.maintain_test_schema! and installs fixture
      # hooks at require time, which belongs in the child (mirroring how the
      # RSpec path requires rspec/core in the parent and lets rails_helper
      # load rspec/rails in the child). Practically unreachable -- activesupport
      # depends on minitest -- but kept as the symmetric guard.
      def require_framework!
        require "minitest"
      rescue LoadError
        raise Coatepec::Error.new(:unsupported_test_framework, "minitest must be in the application's bundle")
      end

      # Selectors first, then flags: run_in_process relies on that order to
      # hand Rails::TestUnit::Runner.load_tests the selectors alone.
      def build_args(selectors, example, seed, fail_fast)
        args = selectors.dup
        args += [name_filter_flag, "/#{Regexp.escape(example)}/"] if example
        args += ["--seed", seed.to_s] if seed
        args << "--fail-fast" if fail_fast

        args
      end

      # Minitest's option parser raises on unknown flags, so the JSON path
      # reaches the reporter in-process (fork) or via the environment (spawn).
      def json_args(_json_path)
        []
      end

      def spawn_command(full_args, json_path)
        [{ "RAILS_ENV" => "test", JSON_PATH_ENV => json_path }, ["bundle", "exec", "ruby", CHILD_ENTRY, *full_args]]
      end

      # Runs in the child. Rails is already booted (config/environment) by
      # the caller. Returns the process exit status.
      def run_in_process(full_args, json_path)
        prepare_child_environment
        configure_minitest!(json_path)

        ::Rails::TestUnit::Runner.load_tests(selectors_from(full_args))
        ::Minitest.run(full_args) ? 0 : 1
      end

      private

      # Minitest 6 renamed -n/--name (options[:filter]) to -i/--include
      # (options[:include]); Rails' own plugin shims -n on 6 with a warning.
      def name_filter_flag
        ::Minitest::VERSION.start_with?("6") ? "-i" : "-n"
      end

      # Every validated selector starts with its root directory name, never
      # with "-", so the flags boundary is exact.
      def selectors_from(full_args)
        full_args.take_while { |arg| !arg.start_with?("-") }
      end

      # PARALLEL_WORKERS must be set before any test file loads: a generated
      # test_helper.rb calls `parallelize(workers: :number_of_processors)`
      # at class-body time and reads the variable right then. Without it, a
      # selection above the parallelization threshold (50 by default) forks
      # a worker tree, each wanting its own database, under this run's one
      # timeout budget. The load-path entry is what `rails test` itself adds
      # (Rails::Command::TestCommand#perform) so `require "test_helper"`
      # resolves.
      def prepare_child_environment
        ENV["PARALLEL_WORKERS"] = "1"
        test_dir = File.join(@project_root, "test")
        $LOAD_PATH.unshift(test_dir) unless $LOAD_PATH.include?(test_dir)
      end

      # rails/test_help pulls in active_support/testing/autorun, which on
      # Minitest 6 already does `Minitest.load :rails`; the guarded call here
      # covers a test_help that does not, without registering Rails' plugin
      # twice (init_plugins would then run plugin_rails_init twice). Minitest
      # 5's #run globs installed gems' plugins itself, so nothing is needed.
      def configure_minitest!(json_path)
        require "rails/test_help"
        ::Minitest.load(:rails) if ::Minitest.respond_to?(:load) && !::Minitest.extensions.include?("rails")
        require_relative "line_filtering"
        LineFiltering.install!
        register_reporter(json_path)
      end

      # Minitest's plugin hook: Minitest.run builds its reporter, then calls
      # plugin_<name>_init for every registered extension with the reporter
      # exposed as Minitest.reporter. Rails' own init only swaps the
      # Summary/Progress reporters, so ours survives it.
      #
      # Ours goes to the *front* of the composite, not the end: Rails'
      # TestUnitReporter implements --fail-fast by raising Interrupt from
      # inside #record, and CompositeReporter delivers #record in list order,
      # so a reporter behind it never sees the very failure that aborted the
      # run -- the one result a fail-fast caller most wants reported.
      def register_reporter(json_path)
        require_relative "json_reporter"
        reporter = JsonReporter.new(json_path, @project_root)
        ::Minitest.extensions << "coatepec" unless ::Minitest.extensions.include?("coatepec")
        ::Minitest.singleton_class.define_method(:plugin_coatepec_init) do |_options|
          ::Minitest.reporter.reporters.unshift(reporter)
        end
      end
    end
  end
end
