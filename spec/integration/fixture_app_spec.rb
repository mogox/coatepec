# frozen_string_literal: true

require "spec_helper"

RSpec.describe "fixture Rails app", type: :integration do
  it "boots under RAILS_ENV=test and exposes Rails.version" do
    stdout, stderr, status = run_in_fixture_app(<<~RUBY)
      require File.join(#{FIXTURE_APP_ROOT.inspect}, "config/environment")
      puts Rails.version
    RUBY

    expect(status).to be_success, stderr
    expect(stdout.strip).to match(/\A(7\.1|8\.1)\./)
  end

  it "has passing and failing example specs available under spec/" do
    expect(File).to exist(File.join(FIXTURE_APP_ROOT, "spec/passing_spec.rb"))
    expect(File).to exist(File.join(FIXTURE_APP_ROOT, "spec/failing_spec.rb"))
  end
end
