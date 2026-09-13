# frozen_string_literal: true

require "securerandom"

module Coatepec
  module Spec
    # Runs a spec selection multiple times, each round with an
    # independently random seed (RSpec's --seed N is equivalent to --order
    # rand:N, confirmed against rspec-core's own option_parser.rb), and
    # groups per-example pass/fail status across rounds by the example's
    # own id -- stable regardless of execution order, since it's derived
    # from declaration position/nesting, not from --order. Composes Runner
    # unchanged, exactly like FactoryProfRunner: every round is a plain,
    # ordinary Runner#run call with a different seed, no strategy override
    # needed (unlike FactoryProfRunner, this feature has no load-time
    # activation trick to fight -- see
    # docs/superpowers/specs/2026-08-13-flaky-spec-detection-design.md).
    class FlakyChecker
      DEFAULT_RUNS = 5
      MAX_TOTAL_SECONDS = 1800 # timeout_seconds * runs must not exceed this
      MAX_ITEMS = 200 # same bound rails_model/FactoryProfRunner use elsewhere

      def initialize(project_root, rails_runtime: nil)
        @runner = Runner.new(project_root, rails_runtime: rails_runtime)
      end

      def call(paths:, example: nil, timeout_seconds: Runner::DEFAULT_TIMEOUT, runs: DEFAULT_RUNS)
        validate_budget!(timeout_seconds, runs)
        rounds = Array.new(runs) { run_one_round(paths, example, timeout_seconds) }
        build_report(rounds)
      end

      private

      def validate_budget!(timeout_seconds, runs)
        return if timeout_seconds * runs <= MAX_TOTAL_SECONDS

        raise Coatepec::Error.new(
          :flaky_check_budget_exceeded,
          "timeout_seconds (#{timeout_seconds}) * runs (#{runs}) exceeds the " \
          "#{MAX_TOTAL_SECONDS}s combined budget -- lower one or both"
        )
      end

      def run_one_round(paths, example, timeout_seconds)
        seed = SecureRandom.random_number(65_536)
        # Every round needs the full roster: a pass in one round is what makes a later failure flaky.
        # stdout is never read from a round, so it is not captured into the result.
        result = @runner.run(
          paths: paths, example: example, seed: seed, fail_fast: false,
          timeout_seconds: timeout_seconds, include_passing: true, include_stdout: "never"
        )
        { seed: seed, status: result[:status], examples: result[:examples] }
      end

      def build_report(rounds)
        by_id = group_examples_by_id(rounds)
        {
          runs: rounds.size,
          rounds: rounds.map { |r| { seed: r[:seed], status: r[:status] } },
          flaky_examples: classify(by_id) { |statuses| statuses.uniq.size > 1 },
          consistently_failing: classify(by_id) { |statuses| statuses.uniq == ["failed"] }
        }
      end

      # Rounds whose RSpec process itself crashed/timed out (not a specific
      # example failing -- the whole run killed before its JSON summary was
      # ever written) contribute no per-example data here. Excluded rather
      # than counted as "every example failed", which would misrepresent a
      # dead process as evidence against examples that never actually ran;
      # the round itself is still visible in the `rounds:` summary.
      def group_examples_by_id(rounds)
        rounds.each_with_object({}) do |round, acc|
          round[:examples].each { |ex| (acc[ex[:id]] ||= { meta: ex, statuses: [] })[:statuses] << ex[:status] }
        end
      end

      def classify(by_id)
        by_id.values.select { |v| yield(v[:statuses]) }.first(MAX_ITEMS).map do |v|
          v[:meta].slice(:id, :description, :file_path, :line_number).merge(
            statuses: v[:statuses],
            pass_count: v[:statuses].count("passed"),
            failure_count: v[:statuses].count("failed")
          )
        end
      end
    end
  end
end
