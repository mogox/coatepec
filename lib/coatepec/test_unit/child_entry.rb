# frozen_string_literal: true

# Entry point for Coatepec::Spec::SpawnStrategy when the selection is
# Minitest: `bundle exec ruby <this file> <selectors and flags>`, run from
# the target app's root with COATEPEC_MINITEST_JSON pointing at the file
# the JSON reporter must write. Boots the app exactly as the warm worker
# would, then hands off to the same TestUnit::Adapter#run_in_process a
# forked child uses, so fork and spawn configure Minitest identically.
#
# `bundle exec` already prepends -rbundler/setup via RUBYOPT; the explicit
# require keeps this script correct if it is ever run without it, and
# mirrors exe/coatepec-worker's ordering rationale (default gems must be
# pinned by Bundler before anything else can auto-activate them).
require "bundler/setup"

$LOAD_PATH.unshift(File.expand_path("../..", __dir__))
require "coatepec/errors"
require "coatepec/test_unit/adapter"

project_root = Dir.pwd
require File.join(project_root, "config/environment")

json_path = ENV.fetch(Coatepec::TestUnit::Adapter::JSON_PATH_ENV)
status = Coatepec::TestUnit::Adapter.new(project_root).run_in_process(ARGV, json_path)
$stdout.flush
$stderr.flush
# rails/test_help requires active_support/testing/autorun, which arms
# Minitest.autorun's at_exit hook. A plain `exit` would therefore run the
# whole suite a second time -- from the now option-stripped ARGV, so without
# the seed/filter/fail-fast -- and overwrite the JSON report with that second
# run's results. exit! skips at_exit handlers, exactly as ForkStrategy's
# child does.
Kernel.exit!(status)
