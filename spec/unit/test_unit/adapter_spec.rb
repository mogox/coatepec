# frozen_string_literal: true

require "spec_helper"
require "minitest"

RSpec.describe Coatepec::TestUnit::Adapter do
  subject(:adapter) { described_class.new("/app") }

  it "identifies itself as minitest" do
    expect(adapter.framework).to eq(:minitest)
  end

  describe "#build_args" do
    it "emits selectors first, then --seed and --fail-fast" do
      expect(adapter.build_args(["test/a_test.rb", "test/b_test.rb:9"], nil, 42, true))
        .to eq(["test/a_test.rb", "test/b_test.rb:9", "--seed", "42", "--fail-fast"])
    end

    it "passes example as a regex-escaped substring via -i on Minitest 6" do
      stub_const("Minitest::VERSION", "6.0.6")

      expect(adapter.build_args(["test/a_test.rb"], "adds 1 + 1", nil, false))
        .to eq(["test/a_test.rb", "-i", "/adds\\ 1\\ \\+\\ 1/"])
    end

    it "uses -n instead on Minitest 5" do
      stub_const("Minitest::VERSION", "5.25.1")

      expect(adapter.build_args(["test/a_test.rb"], "adds", nil, false))
        .to eq(["test/a_test.rb", "-n", "/adds/"])
    end
  end

  it "adds no CLI args for the JSON path (Minitest's parser rejects unknown flags)" do
    expect(adapter.json_args("/tmp/x.json")).to eq([])
  end

  it "spawns the gem's child entry under bundle exec with the JSON path in the environment" do
    env, argv = adapter.spawn_command(["test/a_test.rb", "--seed", "1"], "/tmp/x.json")

    expect(env).to eq("RAILS_ENV" => "test", "COATEPEC_MINITEST_JSON" => "/tmp/x.json")
    expect(argv).to eq(["bundle", "exec", "ruby", described_class::CHILD_ENTRY, "test/a_test.rb", "--seed", "1"])
    expect(File).to exist(described_class::CHILD_ENTRY)
  end

  it "raises unsupported_test_framework when minitest is not loadable" do
    allow(adapter).to receive(:require).with("minitest").and_raise(LoadError)

    expect { adapter.require_framework! }
      .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:unsupported_test_framework) }
  end

  describe "#selectors_from (private)" do
    it "takes every leading argument that is not a flag" do
      expect(adapter.send(:selectors_from, ["test/a_test.rb", "test/b_test.rb:3", "--seed", "7", "-i", "/x/"]))
        .to eq(["test/a_test.rb", "test/b_test.rb:3"])
    end
  end
end
