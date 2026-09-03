# frozen_string_literal: true

require_relative "lib/coatepec/version"

Gem::Specification.new do |spec|
  spec.name = "coatepec"
  spec.version = Coatepec::VERSION
  spec.authors = ["Enrique Mogollan"]
  spec.email = ["emogollan@gmail.com"]

  spec.summary = "Run targeted RSpec examples and introspect Rails structure over MCP, " \
    "without a Rails console"
  spec.description = "Coatepec is a local stdio MCP sidecar that keeps an isolated Rails " \
    "test worker warm so coding agents can run targeted RSpec examples quickly, check " \
    "specs for flakiness, and read routes, models, and controllers through structured " \
    "read-only Rails APIs -- without exposing a general Rails console."
  spec.homepage = "https://github.com/mogox/coatepec"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile .ruby-version])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "railties", ">= 7.1", "< 8.2"

  spec.add_development_dependency "mcp", "~> 1.0"
end
