# frozen_string_literal: true

module Coatepec
  module Spec
    # Runs the test framework in a freshly `Process.spawn`ed process --
    # `bundle exec rspec`, or the Minitest child entry -- (macOS and any
    # platform without a working fork): slower per run since Rails boots
    # from scratch, but avoids fork-safety pitfalls.
    class SpawnStrategy < ProcessStrategy
      private

      def execution_mode = "spawn"

      def start(full_args, out_w, err_w, json_path)
        env, argv = @adapter.spawn_command(full_args, json_path)
        Process.spawn(env, *argv, chdir: @project_root, out: out_w, err: err_w, pgroup: true)
      end
    end
  end
end
