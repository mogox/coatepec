# frozen_string_literal: true

require "bundler"

module Coatepec
  module Worker
    # The parent-process handle to a spawned test worker: owns its pipes,
    # sends NDJSON requests with a response timeout, and detects when the
    # worker has died.
    class Client
      class DisconnectedError < StandardError; end

      def self.spawn(project_root)
        new(project_root).tap(&:start)
      end

      def initialize(project_root)
        @project_root = project_root
        @next_id = 0
      end

      def start
        to_worker_r, @to_worker_write = IO.pipe
        @from_worker_read, from_worker_w = IO.pipe

        @pid = spawn_worker(to_worker_r, from_worker_w)
        to_worker_r.close
        from_worker_w.close
        @protocol = Protocol.new(input: @from_worker_read, output: @to_worker_write)
      end

      def alive?
        return false unless @pid

        Process.kill(0, @pid)
        true
      rescue Errno::ESRCH
        false
      end

      def request(command, args, timeout: 30)
        raise DisconnectedError, "Worker is not running" unless alive?

        id = (@next_id += 1)
        @protocol.write(id: id, command: command, args: args)
        message = read_response(id, timeout)

        message[:ok] ? message[:data] : raise_worker_error(message[:error])
      end

      def stop
        return unless @pid

        Process.kill("TERM", @pid)
        Process.wait(@pid)
      rescue Errno::ESRCH, Errno::ECHILD
        nil
      ensure
        [@to_worker_write, @from_worker_read].each { |io| io && !io.closed? && io.close }
        @pid = nil
      end

      private

      def spawn_worker(to_worker_r, from_worker_w)
        worker_exe = File.expand_path("../../../exe/coatepec-worker", __dir__)
        lib_path = File.expand_path("../..", __dir__)
        # If this process is itself running under a Bundler context (e.g. the
        # host app's own deployment-mode bundle), Bundler.setup has already
        # narrowed GEM_PATH/RUBYOPT to that bundle's install location. Without
        # stripping that, the worker -- which needs the target app's own
        # separately-installed gems -- inherits a GEM_PATH that can't see them
        # and fails with a spurious Bundler::GemNotFound. with_unbundled_env
        # also resets RUBYLIB to its pre-Bundler snapshot, so it must be set
        # explicitly here rather than relying on the caller's environment.
        Bundler.with_unbundled_env do
          Process.spawn(
            { "BUNDLE_GEMFILE" => File.join(@project_root, "Gemfile"), "RUBYLIB" => lib_path },
            RbConfig.ruby, worker_exe, @project_root,
            in: to_worker_r, out: from_worker_w, err: :err, chdir: @project_root
          )
        end
      end

      def read_response(id, timeout)
        ready = IO.select([@from_worker_read], nil, nil, timeout)
        raise DisconnectedError, "Worker timed out responding" unless ready

        message = @protocol.read
        raise DisconnectedError, "Worker closed the connection" if message.nil?
        raise DisconnectedError, "Unexpected response id #{message[:id]} for request #{id}" unless message[:id] == id

        message
      end

      def raise_worker_error(error)
        raise Coatepec::Error.new(error[:code].to_sym, error[:message], details: error[:details] || {})
      end
    end
  end
end
