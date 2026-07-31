# frozen_string_literal: true

module Coatepec
  module Worker
    # Fingerprints Gemfile/Gemfile.lock and boot-relevant files (mtime +
    # size) so WorkerManager can decide whether a bundle change requires the
    # whole sidecar to restart, or a boot-file change just the worker.
    class ChangeDetector
      BUNDLE_FILES = %w[Gemfile Gemfile.lock].freeze
      BOOT_FILES = %w[config/boot.rb config/application.rb config/environment.rb config/environments/test.rb].freeze

      def initialize(project_root)
        @project_root = project_root
      end

      def snapshot
        { bundle: fingerprint(BUNDLE_FILES), boot: fingerprint(BOOT_FILES + initializer_files) }
      end

      def restart_reason(previous_snapshot)
        current = snapshot
        return :sidecar_restart_required if current[:bundle] != previous_snapshot[:bundle]
        return :worker_restart_required if current[:boot] != previous_snapshot[:boot]

        nil
      end

      private

      def initializer_files
        Dir.glob(File.join(@project_root, "config/initializers/**/*.rb"))
           .sort
           .map { |f| f.delete_prefix("#{@project_root}/") }
      end

      def fingerprint(relative_paths)
        relative_paths.each_with_object({}) do |relative_path, acc|
          full_path = File.join(@project_root, relative_path)
          acc[relative_path] = File.exist?(full_path) ? [File.mtime(full_path).to_f, File.size(full_path)] : nil
        end
      end
    end
  end
end
