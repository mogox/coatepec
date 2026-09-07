# frozen_string_literal: true

require "spec_helper"

RSpec.describe Coatepec::Spec::RSpecAdapter do
  subject(:adapter) { described_class.new("/app") }

  it "identifies itself as rspec" do
    expect(adapter.framework).to eq(:rspec)
  end

  describe "#build_args" do
    it "returns the selectors alone by default" do
      expect(adapter.build_args(["spec/a_spec.rb", "spec/b_spec.rb:3"], nil, nil, false))
        .to eq(["spec/a_spec.rb", "spec/b_spec.rb:3"])
    end

    it "adds -e, --seed and --fail-fast in that order" do
      expect(adapter.build_args(["spec/a_spec.rb"], "does a thing", 42, true))
        .to eq(["spec/a_spec.rb", "-e", "does a thing", "--seed", "42", "--fail-fast"])
    end
  end

  it "asks RSpec for progress output plus a JSON file" do
    expect(adapter.json_args("/tmp/x.json"))
      .to eq(["--format", "progress", "--format", "json", "--out", "/tmp/x.json"])
  end

  it "spawns bundle exec rspec in the test environment" do
    env, argv = adapter.spawn_command(["spec/a_spec.rb", "--seed", "1"], "/tmp/x.json")

    expect(env).to eq("RAILS_ENV" => "test")
    expect(argv).to eq(["bundle", "exec", "rspec", "spec/a_spec.rb", "--seed", "1"])
  end

  it "raises unsupported_test_framework when rspec/core is not loadable" do
    allow(adapter).to receive(:require).with("rspec/core").and_raise(LoadError)

    expect { adapter.require_framework! }
      .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:unsupported_test_framework) }
  end
end
