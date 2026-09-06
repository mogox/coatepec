# frozen_string_literal: true

require "json"
require "minitest"

module Coatepec
  module TestUnit
    # A Minitest reporter that writes the run's per-test results to a JSON
    # file in the exact shape RSpec's own `--format json` produces, as far
    # as Coatepec::Spec::Result reads it -- so Result and FlakyChecker need
    # no Minitest-specific code at all. Registered in the child by
    # TestUnit::Adapter#run_in_process; never loaded in the warm worker.
    class JsonReporter < ::Minitest::AbstractReporter
      def initialize(json_path, project_root)
        super()
        @json_path = json_path
        @project_root = File.join(File.expand_path(project_root), "")
        @examples = []
        @started_at = nil
      end

      def start
        @started_at = ::Minitest.clock_time
      end

      def record(result)
        @examples << example_for(result)
      end

      # Written to a sibling and renamed so a child killed mid-write leaves
      # either a complete document or nothing; Result.read_summary already
      # treats a missing/empty file as "no summary".
      def report
        tmp_path = "#{@json_path}.tmp"
        File.write(tmp_path, JSON.generate(document))
        File.rename(tmp_path, @json_path)
      ensure
        File.delete(tmp_path) if tmp_path && File.exist?(tmp_path)
      end

      # This reporter observes; it must never flip the run's exit status.
      def passed?
        true
      end

      private

      def document
        {
          summary: {
            example_count: @examples.size,
            failure_count: @examples.count { |e| e[:status] == "failed" },
            duration: @started_at ? ::Minitest.clock_time - @started_at : 0.0
          },
          examples: @examples
        }
      end

      def example_for(result)
        id = "#{result.klass}##{result.name}"
        file, line = result.source_location
        {
          id: id,
          full_description: id,
          status: status_for(result),
          file_path: relative_path(file),
          line_number: line
        }
      end

      # RSpec's vocabulary: a skip is "pending" (so FlakyChecker's
      # passed/failed counts stay meaningful), an error is just "failed".
      def status_for(result)
        return "pending" if result.skipped?
        return "passed" if result.passed?

        "failed"
      end

      # Never emit the absolute path: same leak rails_controller avoids with
      # Proc#to_s. Matches RSpec's "./spec/..." form for the same file.
      def relative_path(file)
        return nil if file.nil? || file == "unknown"

        expanded = File.expand_path(file)
        return "./#{expanded.delete_prefix(@project_root)}" if expanded.start_with?(@project_root)

        File.basename(expanded)
      end
    end
  end
end
