# frozen_string_literal: true

require "spec_helper"

RSpec.describe Coatepec::Spec::ForkStrategy, type: :integration do
  def run_in_worker(ruby_tail)
    lib_path = File.expand_path("../../../lib", __dir__)
    script = <<~RUBY
      $LOAD_PATH.unshift(#{lib_path.inspect})
      require "coatepec"
      # Production only ever reaches a strategy's #run via
      # Coatepec::Spec::Runner#run, which requires "rspec/core" first. This
      # script calls ForkStrategy#run directly (bypassing Runner), so it
      # must do that require itself or the forked child's
      # RSpec::Core::Runner.run call raises NameError.
      require "rspec/core"
      Coatepec::Worker::RailsRuntime.new(#{FIXTURE_APP_ROOT.inspect}).boot!
      #{ruby_tail}
    RUBY
    run_in_fixture_app(script)
  end

  it "does not accumulate RSpec's own \"files took to load\" time across forked runs from the same warm worker" do
    stdout, stderr, status = run_in_worker(<<~RUBY)
      strategy = Coatepec::Spec::ForkStrategy.new(#{FIXTURE_APP_ROOT.inspect})
      first = strategy.run(["spec/passing_spec.rb"], 30, include_stdout: "always")
      sleep 1.5
      second = strategy.run(["spec/passing_spec.rb"], 30, include_stdout: "always")
      puts JSON.generate(first: first, second: second)
    RUBY

    expect(status).to be_success, stderr
    result = JSON.parse(stdout.lines.last)

    load_time = lambda do |run|
      run["stdout"][/files took ([\d.]+) seconds? to load/, 1].to_f
    end

    expect(result["first"]["status"]).to eq("passed")
    expect(result["second"]["status"]).to eq("passed")
    first_load_time = load_time.call(result["first"])
    second_load_time = load_time.call(result["second"])
    # The bug this guards against: the second run's reported load time grows
    # by roughly the idle gap between calls (~1.5s here), because it's
    # measured against a timestamp frozen once at worker boot and never
    # reset per fork. A fixed run stays close to its own first measurement
    # regardless of how long the worker sat idle beforehand.
    expect(second_load_time).to be < (first_load_time + 0.5)
  end
end
