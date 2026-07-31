# frozen_string_literal: true

module Coatepec
  # A Rails application checkout rooted at an absolute path (must contain a
  # Gemfile); knows where its own and pack/engine/gem spec directories live.
  class Project
    attr_reader :root

    def initialize(root)
      @root = File.expand_path(root)

      return if File.exist?(File.join(@root, "Gemfile"))

      raise Coatepec::Error.new(:project_not_found, "No Gemfile found at #{@root}")
    end

    def spec_root_candidates
      [
        File.join(root, "spec"),
        *Dir.glob(File.join(root, "packs/*/spec")),
        *Dir.glob(File.join(root, "engines/*/spec")),
        *Dir.glob(File.join(root, "gems/*/spec"))
      ].select { |path| File.directory?(path) }
    end
  end
end
