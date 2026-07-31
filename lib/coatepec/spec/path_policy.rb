# frozen_string_literal: true

module Coatepec
  module Spec
    # Validates rails_spec_run's `paths` selectors against the allowed spec
    # roots before any RSpec process is started, rejecting absolute paths,
    # `..` traversal, symlink escapes, non-`_spec.rb` files, and oversized
    # selector lists.
    class PathPolicy
      MAX_SELECTORS = 100

      def initialize(project)
        @project = project
      end

      def validate!(selectors)
        raise Coatepec::Error.new(:invalid_spec_path, "No spec paths given") if selectors.nil? || selectors.empty?
        if selectors.size > MAX_SELECTORS
          raise Coatepec::Error.new(:invalid_spec_path, "At most #{MAX_SELECTORS} spec paths are allowed")
        end

        selectors.map { |selector| validate_one(selector) }
      end

      private

      def validate_one(selector)
        path_part, line_part = selector.to_s.split(":", 2)
        reject_shape!(selector, path_part)
        reject_line_part!(selector, line_part) if line_part

        real_path = resolve_real_path!(selector, path_part)
        reject_escape!(selector, real_path)
        reject_wrong_kind!(selector, real_path)

        line_part ? "#{path_part}:#{line_part}" : path_part
      end

      def resolve_real_path!(selector, path_part)
        full_path = File.expand_path(path_part, @project.root)
        unless File.exist?(full_path)
          raise Coatepec::Error.new(:invalid_spec_path,
                                    "Spec path does not exist: #{selector}")
        end

        File.realpath(full_path)
      rescue Coatepec::Error
        raise
      rescue ArgumentError, Errno::EACCES, Errno::ENOENT, Errno::ENOTDIR => e
        raise Coatepec::Error.new(:invalid_spec_path, "Invalid spec path: #{selector} (#{e.class.name})")
      end

      def reject_shape!(selector, path_part)
        raise Coatepec::Error.new(:invalid_spec_path, "Blank selector") if path_part.to_s.strip.empty?
        if path_part.start_with?("/")
          raise Coatepec::Error.new(:invalid_spec_path,
                                    "Absolute paths are not allowed: #{selector}")
        end
        return unless path_part.split("/").include?("..")

        raise Coatepec::Error.new(:invalid_spec_path, "Path traversal is not allowed: #{selector}")
      end

      def reject_line_part!(selector, line_part)
        return if line_part =~ /\A\d+\z/

        raise Coatepec::Error.new(:invalid_spec_path, "Line number must be digits only: #{selector}")
      end

      def reject_escape!(selector, real_path)
        real_root = File.realpath(@project.root)
        return if real_path == real_root || real_path.start_with?("#{real_root}/")

        raise Coatepec::Error.new(:invalid_spec_path, "Spec path escapes the project root: #{selector}")
      end

      def reject_wrong_kind!(selector, real_path)
        return if under_allowed_root?(real_path) && (File.directory?(real_path) || real_path.end_with?("_spec.rb"))

        raise Coatepec::Error.new(:invalid_spec_path,
                                  "Spec path is not an allowed spec root or _spec.rb file: #{selector}")
      end

      def under_allowed_root?(real_path)
        @project.spec_root_candidates.any? do |candidate|
          real_candidate = File.realpath(candidate)
          real_path == real_candidate || real_path.start_with?("#{real_candidate}/")
        end
      end
    end
  end
end
