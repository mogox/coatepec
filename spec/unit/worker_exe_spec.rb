# frozen_string_literal: true

require "spec_helper"

RSpec.describe "exe/coatepec-worker" do
  # Ruby auto-activates the newest installed version of a default gem (json,
  # among others) the moment anything requires it, and a gem version can't be
  # changed once activated. require "coatepec" pulls in "json" via
  # protocol.rb as its first transitive require, so if that runs before
  # "bundler/setup" pins versions to the target app's Gemfile.lock, Bundler
  # later fails with "already activated X, but your Gemfile requires Y" for
  # any default gem with a newer version installed locally than what's
  # locked. This asserts the fix's ordering structurally, since reliably
  # reproducing "two different default gem versions installed" is not
  # something this suite can control in every environment (including CI).
  it "requires bundler/setup before requiring coatepec" do
    source = File.read(File.expand_path("../../exe/coatepec-worker", __dir__))
    requires = source.scan(/^\s*require\s+["']([^"']+)["']/).flatten

    expect(requires.index("bundler/setup")).to be < requires.index("coatepec")
  end
end
