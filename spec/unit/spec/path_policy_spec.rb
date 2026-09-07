# frozen_string_literal: true

require "spec_helper"
require "coatepec/project"
require "coatepec/spec/path_policy"
require "tmpdir"
require "fileutils"

RSpec.describe Coatepec::Spec::PathPolicy do
  around do |example|
    Dir.mktmpdir do |dir|
      @tmp = dir
      File.write(File.join(@tmp, "Gemfile"), "source 'https://rubygems.org'\n")
      FileUtils.mkdir_p(File.join(@tmp, "spec/models"))
      File.write(File.join(@tmp, "spec/models/widget_spec.rb"), "")
      File.write(File.join(@tmp, "spec/models/widget.rb"), "")
      FileUtils.mkdir_p(File.join(@tmp, "test/models"))
      File.write(File.join(@tmp, "test/models/widget_test.rb"), "")
      File.write(File.join(@tmp, "test/models/helper.rb"), "")
      FileUtils.mkdir_p(File.join(@tmp, "lib"))
      example.run
    end
  end

  subject(:policy) { described_class.new(Coatepec::Project.new(@tmp)) }

  it "accepts a spec file under spec/" do
    expect(policy.validate!(["spec/models/widget_spec.rb"]))
      .to eq(selectors: ["spec/models/widget_spec.rb"], framework: :rspec)
  end

  it "accepts a spec file with a line suffix" do
    expect(policy.validate!(["spec/models/widget_spec.rb:27"]))
      .to eq(selectors: ["spec/models/widget_spec.rb:27"], framework: :rspec)
  end

  it "accepts the spec directory itself" do
    expect(policy.validate!(["spec"])).to eq(selectors: ["spec"], framework: :rspec)
  end

  it "accepts a test file under test/ and classifies it as minitest" do
    expect(policy.validate!(["test/models/widget_test.rb"]))
      .to eq(selectors: ["test/models/widget_test.rb"], framework: :minitest)
  end

  it "accepts a test file with a line suffix" do
    expect(policy.validate!(["test/models/widget_test.rb:12"]))
      .to eq(selectors: ["test/models/widget_test.rb:12"], framework: :minitest)
  end

  it "accepts the test directory itself" do
    expect(policy.validate!(["test/models"])).to eq(selectors: ["test/models"], framework: :minitest)
  end

  it "rejects a non-_test.rb file under test/" do
    expect { policy.validate!(["test/models/helper.rb"]) }
      .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:invalid_spec_path) }
  end

  it "rejects a _spec.rb file placed under test/ and a _test.rb file placed under spec/" do
    File.write(File.join(@tmp, "test/models/odd_spec.rb"), "")
    File.write(File.join(@tmp, "spec/models/odd_test.rb"), "")

    expect { policy.validate!(["test/models/odd_spec.rb"]) }
      .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:invalid_spec_path) }
    expect { policy.validate!(["spec/models/odd_test.rb"]) }
      .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:invalid_spec_path) }
  end

  it "rejects a list that mixes spec and test selectors" do
    expect { policy.validate!(["spec/models/widget_spec.rb", "test/models/widget_test.rb"]) }
      .to raise_error(Coatepec::Error) { |e|
        expect(e.code).to eq(:mixed_test_frameworks)
        expect(e.message).to include("test/models/widget_test.rb")
      }
  end

  it "rejects an empty list" do
    expect { policy.validate!([]) }.to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:invalid_spec_path) }
  end

  it "rejects more than 100 selectors" do
    expect { policy.validate!(Array.new(101) { "spec" }) }
      .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:invalid_spec_path) }
  end

  it "rejects absolute paths" do
    expect { policy.validate!(["/etc/passwd"]) }
      .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:invalid_spec_path) }
  end

  it "rejects path traversal" do
    expect { policy.validate!(["spec/../lib"]) }
      .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:invalid_spec_path) }
  end

  it "rejects paths outside any allowed spec root" do
    expect { policy.validate!(["lib"]) }
      .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:invalid_spec_path) }
  end

  it "rejects non-_spec.rb files" do
    expect { policy.validate!(["spec/models/widget.rb"]) }
      .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:invalid_spec_path) }
  end

  it "rejects a selector for a path that does not exist" do
    expect { policy.validate!(["spec/models/missing_spec.rb"]) }
      .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:invalid_spec_path) }
  end

  it "rejects an invalid line suffix (non-digits)" do
    expect { policy.validate!(["spec/models/widget_spec.rb:27; rm -rf /"]) }
      .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:invalid_spec_path) }
  end

  it "rejects a symlink escape to outside the project root" do
    outside_dir = File.dirname(@tmp)
    outside_spec = File.join(outside_dir, "outside_spec.rb")
    File.write(outside_spec, "")
    begin
      File.symlink(outside_spec, File.join(@tmp, "spec/escaped_spec.rb"))
      expect { policy.validate!(["spec/escaped_spec.rb"]) }
        .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:invalid_spec_path) }
    ensure
      File.unlink(outside_spec) if File.exist?(outside_spec)
    end
  end

  it "rejects a selector containing a NUL byte" do
    expect { policy.validate!(["spec/test\x00_spec.rb"]) }
      .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:invalid_spec_path) }
  end
end
