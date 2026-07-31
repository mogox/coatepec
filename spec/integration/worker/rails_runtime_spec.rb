# frozen_string_literal: true

require "spec_helper"

RSpec.describe Coatepec::Worker::RailsRuntime, type: :integration do
  it "boots the fixture app in test env and reports status" do
    lib_path = File.expand_path("../../../lib", __dir__)
    stdout, stderr, status = run_in_fixture_app(<<~RUBY)
      $LOAD_PATH.unshift(#{lib_path.inspect})
      require "coatepec"
      runtime = Coatepec::Worker::RailsRuntime.new(#{FIXTURE_APP_ROOT.inspect})
      runtime.boot!
      puts JSON.generate(runtime.status)
    RUBY

    expect(status).to be_success, stderr
    result = JSON.parse(stdout.lines.last)

    expect(result["rails_version"]).to match(/\A(7\.1|8\.1)\./)
    expect(result["environment"]).to eq("test")
    expect(result["pid"]).to be_a(Integer)
    expect(result["boot_id"]).to be_a(String)
    expect(result["boot_duration_ms"]).to be >= 0
    expect(result["lifecycle_state"]).to eq("ready")
  end

  it "raises worker_failure when config/environment.rb does not exist" do
    runtime = described_class.new("/nonexistent/project")

    expect { runtime.boot! }.to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:worker_failure) }
  end
end
