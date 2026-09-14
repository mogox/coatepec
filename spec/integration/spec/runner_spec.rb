# frozen_string_literal: true

require "spec_helper"

RSpec.describe Coatepec::Spec::Runner, type: :integration do
  def run_in_worker(ruby_tail)
    lib_path = File.expand_path("../../../lib", __dir__)
    script = <<~RUBY
      $LOAD_PATH.unshift(#{lib_path.inspect})
      require "coatepec"
      Coatepec::Worker::RailsRuntime.new(#{FIXTURE_APP_ROOT.inspect}).boot!
      #{ruby_tail}
    RUBY
    run_in_fixture_app(script)
  end

  it "reports a passing run for a passing spec" do
    stdout, stderr, status = run_in_worker(<<~RUBY)
      result = Coatepec::Spec::Runner.new(#{FIXTURE_APP_ROOT.inspect})
                                     .run(paths: ["spec/passing_spec.rb"], include_stdout: "always")
      puts JSON.generate(result)
    RUBY

    expect(status).to be_success, stderr
    result = JSON.parse(stdout.lines.last)

    expect(result["status"]).to eq("passed")
    expect(result["exit_code"]).to eq(0)
    expect(result["summary"]["example_count"]).to eq(1)
    expect(result["summary"]["failure_count"]).to eq(0)
    expect(result["summary"]["pending_count"]).to eq(0)
    expect(result["summary"]).to include("error_count" => nil, "assertion_count" => nil)
    expect(result["examples"]).to eq([])
    # Regression guard: RSpec's progress-formatter output must land on the
    # child's *stdout* pipe, not leak into stderr or the protocol fd.
    expect(result["stdout"]).to include("1 example, 0 failures")
    expect(result["stdout_truncated"]).to be(false)
  end

  it "returns stdout as null for a passing run by default" do
    stdout, stderr, status = run_in_worker(<<~RUBY)
      result = Coatepec::Spec::Runner.new(#{FIXTURE_APP_ROOT.inspect}).run(paths: ["spec/passing_spec.rb"])
      puts JSON.generate(result)
    RUBY

    expect(status).to be_success, stderr
    result = JSON.parse(stdout.lines.last)

    expect(result["status"]).to eq("passed")
    expect(result).to have_key("stdout")
    expect(result["stdout"]).to be_nil
  end

  it "returns passing examples when include_passing is true" do
    stdout, stderr, status = run_in_worker(<<~RUBY)
      result = Coatepec::Spec::Runner.new(#{FIXTURE_APP_ROOT.inspect})
                                     .run(paths: ["spec/passing_spec.rb"], include_passing: true)
      puts JSON.generate(result)
    RUBY

    expect(status).to be_success, stderr
    result = JSON.parse(stdout.lines.last)

    expect(result["examples"].first["status"]).to eq("passed")
    # RSpec's full_description differs from the example id, so it survives the trim.
    expect(result["examples"].first["description"]).to eq("passing fixture passes")
  end

  it "runs a spec that requires rails_helper against the warm Rails boot" do
    stdout, stderr, status = run_in_worker(<<~RUBY)
      result = Coatepec::Spec::Runner.new(#{FIXTURE_APP_ROOT.inspect})
                                     .run(paths: ["spec/rails_boot_spec.rb"], include_stdout: "always")
      puts JSON.generate(result)
    RUBY

    expect(status).to be_success, stderr
    result = JSON.parse(stdout.lines.last)

    expect(result["status"]).to eq("passed"), result["stderr"]
    expect(result["summary"]["example_count"]).to eq(2)
    expect(result["summary"]["failure_count"]).to eq(0)
    expect(result["stdout"]).to include("2 examples, 0 failures")
  end

  it "reports a failing run for a failing spec" do
    stdout, stderr, status = run_in_worker(<<~RUBY)
      result = Coatepec::Spec::Runner.new(#{FIXTURE_APP_ROOT.inspect}).run(paths: ["spec/failing_spec.rb"])
      puts JSON.generate(result)
    RUBY

    expect(status).to be_success, stderr
    result = JSON.parse(stdout.lines.last)

    expect(result["status"]).to eq("failed")
    expect(result["exit_code"]).not_to eq(0)
    expect(result["summary"]["failure_count"]).to eq(1)
  end

  it "collapses examples that fail with the same error into one block plus a roll-up line" do
    stdout, stderr, status = run_in_worker(<<~RUBY)
      result = Coatepec::Spec::Runner.new(#{FIXTURE_APP_ROOT.inspect}).run(paths: ["spec/repeated_failure_spec.rb"])
      puts JSON.generate(result)
    RUBY

    expect(status).to be_success, stderr
    result = JSON.parse(stdout.lines.last)
    rollup = result["stdout"][/2 more tests failed with this same error: .*/]

    expect(result["summary"]["failure_count"]).to eq(3)
    expect(result["stdout"].scan("RuntimeError:\n").size).to eq(1)
    expect(rollup).to match(/: repeated failure fixture raises \w+, repeated failure fixture raises \w+\z/)
    expect(result["stdout"]).to include("3 examples, 3 failures")
  end

  it "terminates a run that exceeds timeout_seconds" do
    stdout, stderr, status = run_in_worker(<<~RUBY)
      result = Coatepec::Spec::Runner.new(#{FIXTURE_APP_ROOT.inspect}).run(paths: ["spec/slow_spec.rb"], timeout_seconds: 1)
      puts JSON.generate(result)
    RUBY

    expect(status).to be_success, stderr
    result = JSON.parse(stdout.lines.last)

    expect(result["status"]).to eq("failed")
    expect(result["signaled"]).to be(true)
  end

  it "rejects a selector outside the spec allowlist" do
    stdout, stderr, status = run_in_worker(<<~RUBY)
      begin
        Coatepec::Spec::Runner.new(#{FIXTURE_APP_ROOT.inspect}).run(paths: ["../Gemfile"])
        puts "NO ERROR"
      rescue Coatepec::Error => e
        puts JSON.generate(code: e.code)
      end
    RUBY

    expect(status).to be_success, stderr
    expect(JSON.parse(stdout.lines.last)["code"]).to eq("invalid_spec_path")
  end
end
