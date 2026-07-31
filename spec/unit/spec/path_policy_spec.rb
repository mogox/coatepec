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
      FileUtils.mkdir_p(File.join(@tmp, "lib"))
      example.run
    end
  end

  subject(:policy) { described_class.new(Coatepec::Project.new(@tmp)) }

  it "accepts a spec file under spec/" do
    expect(policy.validate!(["spec/models/widget_spec.rb"])).to eq(["spec/models/widget_spec.rb"])
  end

  it "accepts a spec file with a line suffix" do
    expect(policy.validate!(["spec/models/widget_spec.rb:27"])).to eq(["spec/models/widget_spec.rb:27"])
  end

  it "accepts the spec directory itself" do
    expect(policy.validate!(["spec"])).to eq(["spec"])
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
end
