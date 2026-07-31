# frozen_string_literal: true

require "tempfile"

module Coatepec
  module Spec
    # Shared child-process lifecycle for running an isolated RSpec run: spawns
    # (via a subclass's #start), reaps with a timeout budget (TERM then KILL
    # on overrun), and hands the captured output/JSON to Result. Subclasses
    # (ForkStrategy, SpawnStrategy) only implement how the child is started.
    class ProcessStrategy
      def initialize(project_root, project: nil, rails_runtime: nil)
        @project_root = project_root
        @project = project
        @rails_runtime = rails_runtime
      end

      def run(args, timeout_seconds)
        out_r, out_w = IO.pipe
        err_r, err_w = IO.pipe
        json_path = Tempfile.create(["coatepec-rspec", ".json"], &:path)

        pid = start_or_release(args, out_w, err_w, json_path, [out_r, err_r])
        [out_w, err_w].each(&:close)

        reap(pid, out_r, err_r, timeout_seconds, json_path)
      end

      private

      # Subclasses start a process and return its pid; RSpec's own output
      # must be wired to out_w/err_w.
      def start(_full_args, _out_w, _err_w)
        raise NotImplementedError, "#{self.class} must implement #start"
      end

      # A failed #start (Process.fork can raise Errno::EAGAIN/ENOMEM outright)
      # leaves no child to reap, so the fds and tempfile #reap would have
      # released have to be freed here. The original exception still reaches
      # the caller -- only GuardedForkStrategy intercepts it to fall back.
      def start_or_release(args, out_w, err_w, json_path, read_ends)
        start(args + json_format_args(json_path), out_w, err_w)
      rescue StandardError
        ([out_w, err_w] + read_ends).each { |io| io.close unless io.closed? }
        File.delete(json_path) if File.exist?(json_path)
        raise
      end

      def json_format_args(json_path)
        ["--format", "progress", "--format", "json", "--out", json_path]
      end

      def reap(pid, out_r, err_r, timeout_seconds, json_path)
        status = wait_with_timeout(pid, timeout_seconds)
        result = Result.build(pid: pid, status: status, out_r: out_r, err_r: err_r, json_path: json_path)
        [out_r, err_r].each(&:close)
        result
      ensure
        File.delete(json_path) if File.exist?(json_path)
      end

      def wait_with_timeout(pid, timeout_seconds)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds
        poll_until(pid, deadline) || terminate_and_wait(pid)
      end

      def poll_until(pid, deadline)
        loop do
          _pid, status = Process.waitpid2(pid, Process::WNOHANG)
          return status if status
          return nil if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

          sleep 0.05
        end
      end

      def terminate_and_wait(pid)
        status = terminate(pid)
        return status if status

        _pid, status = Process.waitpid2(pid)
        status
      rescue Errno::ECHILD
        nil
      end

      # TERM, wait briefly, then KILL — this needs the multi-step escalation
      # so a hung child gets a graceful chance before the hard kill. If the
      # WNOHANG poll below reaps the child, that reap is the *only* wait
      # this pid will ever satisfy — the status must be returned here
      # rather than discarded, or the caller's follow-up waitpid2 raises
      # Errno::ECHILD.
      def terminate(pid)
        Process.kill("TERM", -pid)
        3.times do
          sleep 0.2
          _pid, status = Process.waitpid2(pid, Process::WNOHANG)
          return status if status
        end
        Process.kill("KILL", -pid)
        nil
      rescue Errno::ESRCH
        nil
      end
    end
  end
end
