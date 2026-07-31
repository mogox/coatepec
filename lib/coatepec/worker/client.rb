# frozen_string_literal: true

module Coatepec
  module Worker
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

        worker_exe = File.expand_path("../../../exe/coatepec-worker", __dir__)
        @pid = Process.spawn(
          { "BUNDLE_GEMFILE" => File.join(@project_root, "Gemfile") },
          RbConfig.ruby, worker_exe, @project_root,
          in: to_worker_r, out: from_worker_w, err: :err, chdir: @project_root
        )
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
