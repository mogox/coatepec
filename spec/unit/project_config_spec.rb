# frozen_string_literal: true

require "spec_helper"
require "coatepec/project_config"
require "tmpdir"

RSpec.describe Coatepec::ProjectConfig do
  around do |example|
    Dir.mktmpdir do |dir|
      @tmp = dir
      example.run
    end
  end

  it "defaults macos_fork? to false and macos_fork_unsafe_gems to [] when there is no config file" do
    config = described_class.new(@tmp)

    expect(config.macos_fork?).to be(false)
    expect(config.macos_fork_unsafe_gems).to eq([])
  end

  it "reads macos_fork: true from .coatepec.yml" do
    File.write(File.join(@tmp, ".coatepec.yml"), "macos_fork: true\n")

    expect(described_class.new(@tmp).macos_fork?).to be(true)
  end

  it "reads macos_fork: false from .coatepec.yml" do
    File.write(File.join(@tmp, ".coatepec.yml"), "macos_fork: false\n")

    expect(described_class.new(@tmp).macos_fork?).to be(false)
  end

  it "reads macos_fork_unsafe_gems as an array of strings" do
    File.write(File.join(@tmp, ".coatepec.yml"), "macos_fork_unsafe_gems:\n  - some_gem\n  - other_gem\n")

    expect(described_class.new(@tmp).macos_fork_unsafe_gems).to eq(%w[some_gem other_gem])
  end

  it "defaults macos_fork_unsafe_gems to [] when the key is absent" do
    File.write(File.join(@tmp, ".coatepec.yml"), "macos_fork: true\n")

    expect(described_class.new(@tmp).macos_fork_unsafe_gems).to eq([])
  end

  it "raises invalid_config when the file is not a YAML mapping" do
    File.write(File.join(@tmp, ".coatepec.yml"), "- just\n- a\n- list\n")

    expect { described_class.new(@tmp) }
      .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:invalid_config) }
  end

  it "raises invalid_config on malformed YAML syntax" do
    File.write(File.join(@tmp, ".coatepec.yml"), "macos_fork: [true\n")

    expect { described_class.new(@tmp) }
      .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:invalid_config) }
  end
end
