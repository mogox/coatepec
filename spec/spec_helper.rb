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

# Integration specs need the fixture app's test database migrated with this
# project's fixture schema (the Owner/Widget models Coatepec introspects).
# Guarded on file existence so unit specs (which never boot Rails) don't pay
# any subprocess cost on a checkout that already has it, and a fresh CI
# checkout -- which only ever gets db/schema.rb from git, never the
# gitignored .sqlite3 file itself -- gets it prepared automatically, whether
# rspec was invoked via `rake` or directly (both paths load this file).
# Reloads whenever `db/schema.rb` is newer than the database file, not just when the file is
# missing entirely, so a `git pull` that changes the schema doesn't silently leave a stale local
# database in place.

def fixture_db_needs_reload?(db_path, schema_path)
  !File.exist?(db_path) || File.mtime(schema_path) > File.mtime(db_path)
end

db_path = File.join(FIXTURE_APP_ROOT, "storage/test.sqlite3")
schema_path = File.join(FIXTURE_APP_ROOT, "db/schema.rb")
if fixture_db_needs_reload?(db_path, schema_path)
  Bundler.with_unbundled_env do
    system(
      { "BUNDLE_GEMFILE" => File.join(FIXTURE_APP_ROOT, "Gemfile"), "RAILS_ENV" => "test" },
      "bundle", "exec", "rails", "db:schema:load",
      chdir: FIXTURE_APP_ROOT, out: File::NULL, err: File::NULL, exception: true
    )
  end
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
