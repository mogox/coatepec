# frozen_string_literal: true

module Coatepec
  # A Rails application checkout rooted at an absolute path (must contain a
  # Gemfile); knows where its own and pack/engine/gem spec and test
  # directories live.
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

    def test_root_candidates
      [
        File.join(root, "test"),
        *Dir.glob(File.join(root, "packs/*/test")),
        *Dir.glob(File.join(root, "engines/*/test")),
        *Dir.glob(File.join(root, "gems/*/test"))
      ].select { |path| File.directory?(path) }
    end

    def config
      @config ||= ProjectConfig.new(root)
    end
  end
end
