# frozen_string_literal: true

module Coatepec
  module Spec
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
        STDOUT.reopen(out_w)
        STDERR.reopen(err_w)
      end
    end
  end
end
