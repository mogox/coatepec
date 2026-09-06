# frozen_string_literal: true

module Coatepec
  module Spec
    # Validates rails_spec_run's `paths` selectors against the allowed spec
    # and test roots before any test process is started, rejecting absolute
    # paths, `..` traversal, symlink escapes, files that are neither
    # `_spec.rb` under a spec root nor `_test.rb` under a test root, and
    # oversized selector lists. Also classifies the whole list as RSpec or
    # Minitest from the selectors' shape: a list may not mix the two.
    class PathPolicy
      MAX_SELECTORS = 100

      KINDS = {
        rspec: { roots: :spec_root_candidates, suffix: "_spec.rb" },
        minitest: { roots: :test_root_candidates, suffix: "_test.rb" }
      }.freeze

      def initialize(project)
        @project = project
      end

      # Returns { selectors: [...], framework: :rspec | :minitest }.
      def validate!(selectors)
        raise Coatepec::Error.new(:invalid_spec_path, "No spec paths given") if selectors.nil? || selectors.empty?
        if selectors.size > MAX_SELECTORS
          raise Coatepec::Error.new(:invalid_spec_path, "At most #{MAX_SELECTORS} spec paths are allowed")
        end

        classified = selectors.map { |selector| validate_one(selector) }
        { selectors: classified.map { |c| c[:selector] }, framework: single_framework!(classified) }
      end

      private

      def validate_one(selector)
        path_part, line_part = selector.to_s.split(":", 2)
        reject_shape!(selector, path_part)
        reject_line_part!(selector, line_part) if line_part

        real_path = resolve_real_path!(selector, path_part)
        reject_escape!(selector, real_path)
        framework = framework_for!(selector, real_path)

        { selector: line_part ? "#{path_part}:#{line_part}" : path_part, framework: framework }
      end

      def single_framework!(classified)
        frameworks = classified.map { |c| c[:framework] }.uniq
        return frameworks.first if frameworks.size == 1

        raise Coatepec::Error.new(:mixed_test_frameworks, mixed_frameworks_message(classified))
      end

      # Names the minority selectors: the ones an agent most likely added by
      # mistake to an otherwise single-framework call.
      def mixed_frameworks_message(classified)
        majority = classified.group_by { |c| c[:framework] }.max_by { |_, list| list.size }.first
        odd = classified.reject { |c| c[:framework] == majority }.map { |c| c[:selector] }
        "A single call may not mix RSpec and Minitest selectors; these do not match the others: #{odd.join(", ")}"
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

      # A directory under a root is that root's kind; a file must also carry
      # the kind's suffix. The two root sets never overlap (spec/ vs test/),
      # so the iteration order does not matter.
      def framework_for!(selector, real_path)
        KINDS.each do |framework, kind|
          next unless under_any_root?(real_path, @project.public_send(kind[:roots]))
          return framework if File.directory?(real_path) || real_path.end_with?(kind[:suffix])
        end

        raise Coatepec::Error.new(
          :invalid_spec_path,
          "Spec path is not an allowed spec/test root, a _spec.rb file under spec/, " \
          "or a _test.rb file under test/: #{selector}"
        )
      end

      def under_any_root?(real_path, roots)
        roots.any? do |candidate|
          real_candidate = File.realpath(candidate)
          real_path == real_candidate || real_path.start_with?("#{real_candidate}/")
        end
      end
    end
  end
end
