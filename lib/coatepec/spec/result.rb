# frozen_string_literal: true

require "json"

module Coatepec
  module Spec
    # Turns a finished test child's exit status, captured output (each capped
    # at MAX_OUTPUT_BYTES) and the framework's JSON summary into the flat
    # result hash rails_spec_run returns. Passing examples are omitted unless
    # include_passing; stdout is kept for failing runs unless include_stdout
    # says always or never, and its repeated failure blocks are collapsed by FailureCollapser.
    module Result
      MAX_OUTPUT_BYTES = 256 * 1024
      MAX_EXAMPLES = 500
      STDOUT_MODES = %w[failures always never].freeze

      module_function

      def build(pid:, status:, out_r:, err_r:, json_path:, include_passing: false, include_stdout: "failures")
        validate_stdout_mode!(include_stdout)
        captured = read_bounded(out_r)
        stdout_result = keep_stdout?(include_stdout, status) ? collapse_failures(captured) : captured.merge(text: nil)
        stderr_result = read_bounded(err_r)
        summary = read_summary(json_path)

        base(pid, status, stdout_result, stderr_result).merge(
          summary: summary && summary_fields(summary),
          examples: selected_examples(summary, include_passing).map { |e| example_fields(e) }
        )
      end

      # A green run's stdout is progress dots and a summary line the payload already carries as counts.
      def keep_stdout?(mode, status)
        mode == "always" || (mode == "failures" && !passed?(status))
      end

      def passed?(status)
        status.exited? && status.exitstatus.zero?
      end

      # The MCP schema enforces the enum; this guards the worker command against any other caller.
      def validate_stdout_mode!(mode)
        return if STDOUT_MODES.include?(mode)

        raise Coatepec::Error.new(:invalid_include_stdout,
                                  "include_stdout must be one of #{STDOUT_MODES.join(", ")}, got #{mode.inspect}")
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

      def base(pid, status, stdout_result, stderr_result)
        {
          status: passed?(status) ? "passed" : "failed",
          exit_code: status.exitstatus,
          **process_fields(pid, status),
          stdout: stdout_result[:text],
          stdout_truncated: stdout_result[:truncated],
          stderr: stderr_result[:text],
          stderr_truncated: stderr_result[:truncated]
        }
      end

      # A normal exit has nothing to say about signals; these five appear only when the child did not exit.
      def process_fields(pid, status)
        return {} if status.exited?

        { child_pid: pid, signaled: status.signaled?, termsig: status.termsig, stopsig: status.stopsig,
          coredump: status.respond_to?(:coredump?) ? status.coredump? : false }
      end

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
