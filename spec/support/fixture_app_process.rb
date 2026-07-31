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
    Bundler.with_unbundled_env do
      Open3.capture3(env, RbConfig.ruby, "-I", lib_path, "-e", ruby_code, chdir: FIXTURE_APP_ROOT)
    end
  end
end

RSpec.configure { |config| config.include FixtureAppProcess, type: :integration }
