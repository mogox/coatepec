# frozen_string_literal: true

module Coatepec
  module Spec
    # Runs RSpec in a `Process.fork`ed child (Linux only): cheap and reuses
    # the warm worker's loaded Rails boot, but isolated from the parent's
    # ActiveRecord connections and global state.
    class ForkStrategy < ProcessStrategy
      private

      def start(full_args, out_w, err_w)
        Process.fork do
          Process.setpgid(0, 0)
          redirect_output(out_w, err_w)
          # Forked children must not share the parent's live DB sockets.
          ActiveRecord::Base.connection_handler.clear_all_connections! if defined?(ActiveRecord::Base)

          status = RSpec::Core::Runner.run(full_args, $stderr, $stdout)
          $stdout.flush
          $stderr.flush
          Kernel.exit!(status)
        end
      end

      # rubocop:disable Style/GlobalStdStream -- exe/coatepec-worker aliases $stdout to
      # $stderr so Rails boot output can't corrupt the NDJSON protocol on fd 1. That
      # makes $stdout/$stderr the same object here, so only the STDOUT/STDERR
      # constants can move the underlying fds -- and fd 1 must move off the
      # protocol pipe.
      def redirect_output(out_w, err_w)
        STDOUT.reopen(out_w)
        STDERR.reopen(err_w)
        $stdout = STDOUT
        $stderr = STDERR
      end
      # rubocop:enable Style/GlobalStdStream
    end
  end
end
