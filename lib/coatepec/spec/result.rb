# frozen_string_literal: true

require "json"

module Coatepec
  module Spec
    # Turns a finished test child's exit status, captured output (each capped
    # at MAX_OUTPUT_BYTES) and the framework's JSON summary into the flat
    # result hash rails_spec_run returns. Passing examples are omitted unless
    # include_passing; stdout is nulled when include_stdout is false, and
    # otherwise its repeated failure blocks are collapsed by FailureCollapser.
    module Result
      MAX_OUTPUT_BYTES = 256 * 1024
      MAX_EXAMPLES = 500

      module_function

      def build(pid:, status:, out_r:, err_r:, json_path:, include_passing: false, include_stdout: true)
        captured = read_bounded(out_r)
        stdout_result = include_stdout ? collapse_failures(captured) : captured.merge(text: nil)
        stderr_result = read_bounded(err_r)
        summary = read_summary(json_path)

        base(pid, status, stdout_result, stderr_result).merge(
          summary: summary && summary_fields(summary),
          examples: selected_examples(summary, include_passing).map { |e| example_fields(e) }
        )
      end

      # Repeated failure text is the bulk of a failing run's stdout; examples[] already names every failing test.
      def collapse_failures(captured)
        captured.merge(text: FailureCollapser.call(captured[:text]))
      end

      # Passing examples are dropped before the cap so a large green run never crowds out its failures.
      def selected_examples(summary, include_passing)
        examples = summary&.dig("examples") || []
        examples = examples.reject { |e| e["status"] == "passed" } unless include_passing
        examples.first(MAX_EXAMPLES)
      end

      # rubocop:disable Metrics/MethodLength -- one flat hash literal mapping
      # Process::Status/captured-output fields to the result payload's own
      # field names; splitting it would scatter that 1:1 mapping across
      # methods for no readability gain.
      def base(pid, status, stdout_result, stderr_result)
        {
          status: status.exited? && status.exitstatus.zero? ? "passed" : "failed",
          exit_code: status.exitstatus,
          child_pid: pid,
          signaled: status.signaled?,
          termsig: status.termsig,
          stopsig: status.stopsig,
          coredump: status.respond_to?(:coredump?) ? status.coredump? : false,
          stdout: stdout_result[:text],
          stdout_truncated: stdout_result[:truncated],
          stderr: stderr_result[:text],
          stderr_truncated: stderr_result[:truncated]
        }
      end
      # rubocop:enable Metrics/MethodLength

      def read_summary(json_path)
        return nil unless File.exist?(json_path) && !File.empty?(json_path)

        JSON.parse(File.read(json_path))
      end

      def summary_fields(summary)
        {
          example_count: summary.dig("summary", "example_count"),
          failure_count: summary.dig("summary", "failure_count"),
          pending_count: summary.dig("summary", "pending_count"),
          duration: summary.dig("summary", "duration")
        }
      end

      # description is Minitest's id by construction and RSpec's full_description; only emit it when it adds something.
      def example_fields(example)
        description = example["full_description"]
        fields = {
          id: example["id"],
          description: description,
          status: example["status"],
          file_path: example["file_path"],
          line_number: example["line_number"]
        }
        fields.delete(:description) if description.nil? || description == example["id"]
        fields
      end

      def read_bounded(io)
        data = io.read.to_s
        truncated = data.bytesize > MAX_OUTPUT_BYTES
        data = data.byteslice(-MAX_OUTPUT_BYTES, MAX_OUTPUT_BYTES) if truncated
        { text: data, truncated: truncated }
      end
    end
  end
end
