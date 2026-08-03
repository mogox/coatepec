# frozen_string_literal: true

module FixtureAppProcess
  def run_in_fixture_app(ruby_code)
    lib_path = File.expand_path("../../lib", __dir__)
    env = {
      "BUNDLE_GEMFILE" => File.join(FIXTURE_APP_ROOT, "Gemfile"),
      "RAILS_ENV" => "test"
    }

    # Mirrors Worker::Client#spawn_worker's Bundler.with_unbundled_env: this
    # process runs under coatepec's own bundle, whose GEM_PATH must not leak
    # into the fixture app's separately-installed gems.
    #
    # Also mirrors exe/coatepec-worker's require "bundler/setup" ordering:
    # every caller's script requires "coatepec" (which pulls in "json" via
    # protocol.rb) as its first real line. Ruby auto-activates the newest
    # installed version of a default gem the moment anything requires it,
    # and once activated it can't be changed -- so without bundler/setup
    # running first, that would fail with "already activated X, but your
    # Gemfile requires Y" for any default gem with a newer version
    # installed locally than what this fixture app's Gemfile.lock pins.
    script = "require \"bundler/setup\"\n#{ruby_code}"

    Bundler.with_unbundled_env do
      Open3.capture3(env, RbConfig.ruby, "-I", lib_path, "-e", script, chdir: FIXTURE_APP_ROOT)
    end
  end
end

RSpec.configure { |config| config.include FixtureAppProcess, type: :integration }
