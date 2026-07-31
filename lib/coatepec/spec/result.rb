# frozen_string_literal: true

require "json"

module Coatepec
  module Spec
    module Result
      MAX_OUTPUT_BYTES = 256 * 1024

      module_function

      def build(pid:, status:, out_r:, err_r:, json_path:)
        stdout_result = read_bounded(out_r)
        stderr_result = read_bounded(err_r)
        summary = read_summary(json_path)

        base(pid, status, stdout_result, stderr_result).merge(
          summary: summary && summary_fields(summary),
          examples: (summary&.fetch("examples", []) || []).first(500).map { |e| example_fields(e) }
        )
      end

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

      def read_summary(json_path)
        return nil unless File.exist?(json_path) && !File.empty?(json_path)

        JSON.parse(File.read(json_path))
      end

      def summary_fields(summary)
        {
          example_count: summary.dig("summary", "example_count"),
          failure_count: summary.dig("summary", "failure_count"),
          duration: summary.dig("summary", "duration")
        }
      end

      def example_fields(example)
        {
          id: example["id"],
          description: example["full_description"],
          status: example["status"],
          file_path: example["file_path"],
          line_number: example["line_number"]
        }
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
