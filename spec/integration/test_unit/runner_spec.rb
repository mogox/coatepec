# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Coatepec::Spec::Runner with Minitest selectors", type: :integration do
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

  def run_runner(call_args)
    stdout, stderr, status = run_in_worker(<<~RUBY)
      result = Coatepec::Spec::Runner.new(#{FIXTURE_APP_ROOT.inspect}).run(#{call_args})
      puts JSON.generate(result)
    RUBY
    expect(status).to be_success, stderr
    JSON.parse(stdout.lines.last)
  end

  it "runs a whole Minitest file and reports per-test results in the RSpec result shape" do
    result = run_runner('paths: ["test/models/passing_test.rb"]')

    expect(result["status"]).to eq("passed"), result["stderr"]
    expect(result["exit_code"]).to eq(0)
    expect(result["summary"]).to include("example_count" => 2, "failure_count" => 0)
    expect(result["examples"].map { |e| e["id"] })
      .to contain_exactly("PassingTest#test_adds", "PassingTest#test_reaches_the_database")
    expect(result["examples"].map { |e| e["file_path"] }.uniq).to eq(["./test/models/passing_test.rb"])
    expect(result["examples"].map { |e| e["status"] }.uniq).to eq(["passed"])
    # Rails' own reporter output lands on the child's stdout pipe.
    expect(result["stdout"]).to include("2 runs, 2 assertions, 0 failures")
  end

  it "selects a single test by file:LINE" do
    result = run_runner('paths: ["test/models/passing_test.rb:9"]')

    expect(result["status"]).to eq("passed"), result["stderr"]
    expect(result["examples"].map { |e| e["id"] }).to eq(["PassingTest#test_reaches_the_database"])
    expect(result["examples"].first["line_number"]).to eq(9)
  end

  it "runs a directory selector" do
    result = run_runner('paths: ["test/models"]')

    expect(result["summary"]["example_count"]).to eq(7)
  end

  it "selects by example substring" do
    result = run_runner('paths: ["test/models/passing_test.rb"], example: "reaches the"')

    expect(result["examples"].map { |e| e["id"] }).to eq(["PassingTest#test_reaches_the_database"])
  end

  it "reports an assertion failure and an error both as failed, and a skip as pending" do
    failing = run_runner('paths: ["test/models/failing_test.rb"]')
    skipped = run_runner('paths: ["test/models/skipped_test.rb"]')

    expect(failing["status"]).to eq("failed")
    expect(failing["exit_code"]).not_to eq(0)
    expect(failing["summary"]).to include("example_count" => 2, "failure_count" => 2)
    expect(failing["examples"].map { |e| e["status"] }.uniq).to eq(["failed"])
    expect(skipped["status"]).to eq("passed")
    expect(skipped["examples"].first["status"]).to eq("pending")
  end

  it "honours seed and fail_fast" do
    result = run_runner('paths: ["test/models/failing_test.rb"], seed: 1234, fail_fast: true')

    expect(result["stdout"]).to include("--seed 1234")
    expect(result["summary"]["example_count"]).to eq(1)
  end

  it "rejects a call that mixes spec and test selectors" do
    stdout, stderr, status = run_in_worker(<<~RUBY)
      begin
        Coatepec::Spec::Runner.new(#{FIXTURE_APP_ROOT.inspect})
                              .run(paths: ["spec/passing_spec.rb", "test/models/passing_test.rb"])
        puts "NO ERROR"
      rescue Coatepec::Error => e
        puts JSON.generate(code: e.code)
      end
    RUBY

    expect(status).to be_success, stderr
    expect(JSON.parse(stdout.lines.last)["code"]).to eq("mixed_test_frameworks")
  end

  it "still runs RSpec selectors unchanged from the same worker" do
    result = run_runner('paths: ["spec/passing_spec.rb"]')

    expect(result["status"]).to eq("passed")
    expect(result["stdout"]).to include("1 example, 0 failures")
  end
end
