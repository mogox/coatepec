# frozen_string_literal: true

require "yaml"

module Coatepec
  # Optional per-project settings loaded from `.coatepec.yml` at the
  # project root. A missing file means every setting takes its default --
  # this file has never been required for Coatepec to work.
  class ProjectConfig
    # Mirrors the MCP input schemas so a value the file accepts is one the tool accepts.
    DEFAULT_KEYS = {
      "spec_run" => {
        "include_passing" => { boolean: true },
        "include_stdout" => { enum: %w[failures always never] },
        "timeout_seconds" => { range: 1..900 }
      },
      "routes" => { "engines" => { enum: %w[include exclude only] } }
    }.freeze

    def initialize(root)
      @data = load(root)
      @defaults = validate_defaults!(@data["defaults"] || {}) # a bare `defaults:` key means none
    end

    def defaults_for(tool)
      @defaults.fetch(tool.to_s, {}).transform_keys(&:to_sym)
    end

    # Forking is the macOS default since 0.9.0; `macos_fork: false` opts a project out.
    def macos_fork?
      @data.fetch("macos_fork", true) ? true : false
    end

    def macos_fork_unsafe_gems
      Array(@data["macos_fork_unsafe_gems"]).map(&:to_s)
    end

    private

    def validate_defaults!(defaults)
      invalid!("defaults must be a mapping of tool names") unless defaults.is_a?(Hash)
      defaults.each do |tool, keys|
        rules = DEFAULT_KEYS[tool.to_s] || invalid!("defaults.#{tool} is not a configurable tool")
        invalid!("defaults.#{tool} must be a mapping") unless keys.is_a?(Hash)
        keys.each { |key, value| validate_default!(tool, key, value, rules[key.to_s]) }
      end
      defaults
    end

    def validate_default!(tool, key, value, rule)
      invalid!("defaults.#{tool}.#{key} is not a configurable input") unless rule
      ok = if rule[:boolean] then [true, false].include?(value)
           elsif rule[:enum] then rule[:enum].include?(value)
           else value.is_a?(Integer) && rule[:range].cover?(value)
           end
      invalid!("defaults.#{tool}.#{key}: #{value.inspect} is not allowed") unless ok
    end

    def invalid!(message)
      raise Coatepec::Error.new(:invalid_config, "Invalid .coatepec.yml: #{message}")
    end

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
