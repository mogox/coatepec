# frozen_string_literal: true

require "coatepec"
require "open3"

# Worker::Client repoints its spawned worker subprocess's BUNDLE_GEMFILE at
# the fixture Rails app, which has no dependency on this local coatepec
# checkout. RUBYLIB keeps coatepec's own lib/ on that child's $LOAD_PATH so
# `require "coatepec"` still resolves there, without Worker::Client needing
# to know about it directly. The outer coatepec CLI process does not repoint
# BUNDLE_GEMFILE — it runs under coatepec's own bundle, as it does in
# production.
ENV["RUBYLIB"] = File.expand_path("../lib", __dir__)

Dir[File.join(__dir__, "support/**/*.rb")].sort.each { |f| require f }

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
