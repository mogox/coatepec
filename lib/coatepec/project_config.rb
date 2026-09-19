# frozen_string_literal: true

require "yaml"

module Coatepec
  # Optional per-project settings loaded from `.coatepec.yml` at the
  # project root. A missing file means every setting takes its default --
  # this file has never been required for Coatepec to work.
  class ProjectConfig
    def initialize(root)
      @data = load(root)
    end

    # Forking is the macOS default since 0.9.0; `macos_fork: false` opts a project out.
    def macos_fork?
      @data.fetch("macos_fork", true) ? true : false
    end

    def macos_fork_unsafe_gems
      Array(@data["macos_fork_unsafe_gems"]).map(&:to_s)
    end

    private

    def load(root)
      path = File.join(root, ".coatepec.yml")
      return {} unless File.exist?(path)

      parse(File.read(path))
    # Psych::Exception, not just SyntaxError: safe_load also raises
    # AliasesNotEnabled (anchors/aliases) and DisallowedClass (e.g. an
    # unquoted date), which are equally the user's config being wrong.
    rescue Psych::Exception => e
      raise Coatepec::Error.new(:invalid_config, "Invalid .coatepec.yml: #{e.message}")
    end

    def parse(text)
      data = YAML.safe_load(text)
      return {} if data.nil?
      return data if data.is_a?(Hash)

      raise Coatepec::Error.new(:invalid_config, ".coatepec.yml must be a YAML mapping")
    end
  end
end
