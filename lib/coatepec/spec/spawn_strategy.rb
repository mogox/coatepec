# frozen_string_literal: true

module Coatepec
  module Spec
    # Runs RSpec in a freshly `Process.spawn`ed `bundle exec rspec` (macOS
    # and any platform without a working fork): slower per run since Rails
    # boots from scratch, but avoids fork-safety pitfalls.
    class SpawnStrategy < ProcessStrategy
      private

      def start(full_args, out_w, err_w)
        Process.spawn(
          { "RAILS_ENV" => "test" }, "bundle", "exec", "rspec", *full_args,
          chdir: @project_root, out: out_w, err: err_w, pgroup: true
        )
      end
    end
  end
end
