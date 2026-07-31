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

      def redirect_output(out_w, err_w)
        $stdout.reopen(out_w)
        $stderr.reopen(err_w)
        $stdout.reopen(out_w)
        $stderr.reopen(err_w)
      end
    end
  end
end
