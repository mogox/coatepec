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

  it "defaults macos_fork? to true and macos_fork_unsafe_gems to [] when there is no config file" do
    config = described_class.new(@tmp)

    expect(config.macos_fork?).to be(true)
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

  it "treats a non-boolean macos_fork as its truthiness" do
    File.write(File.join(@tmp, ".coatepec.yml"), "macos_fork: maybe\n")

    expect(described_class.new(@tmp).macos_fork?).to be(true)
  end

  it "treats an empty macos_fork value as opting out" do
    File.write(File.join(@tmp, ".coatepec.yml"), "macos_fork:\n")

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

  # safe_load rejects these as Psych::DisallowedClass/AliasesNotEnabled --
  # neither is a Psych::SyntaxError, so both used to escape as raw Psych
  # exceptions and surface as :internal_error.
  it "raises invalid_config for a value safe_load disallows (an unquoted date)" do
    File.write(File.join(@tmp, ".coatepec.yml"), "macos_fork: 2026-01-01\n")

    expect { described_class.new(@tmp) }
      .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:invalid_config) }
  end

  it "raises invalid_config for YAML aliases" do
    File.write(File.join(@tmp, ".coatepec.yml"), "a: &anchor [x]\nmacos_fork_unsafe_gems: *anchor\n")

    expect { described_class.new(@tmp) }
      .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:invalid_config) }
  end

  it "returns {} from defaults_for when there is no file or no defaults section" do
    expect(described_class.new(@tmp).defaults_for(:spec_run)).to eq({})
    File.write(File.join(@tmp, ".coatepec.yml"), "macos_fork: true\n")
    expect(described_class.new(@tmp).defaults_for(:routes)).to eq({})
  end

  it "reads validated defaults per tool with symbol keys" do
    File.write(File.join(@tmp, ".coatepec.yml"), <<~YAML)
      defaults:
        spec_run:
          include_passing: true
          include_stdout: always
          timeout_seconds: 300
        routes:
          engines: include
    YAML

    config = described_class.new(@tmp)

    expect(config.defaults_for(:spec_run)).to eq(include_passing: true, include_stdout: "always", timeout_seconds: 300)
    expect(config.defaults_for(:routes)).to eq(engines: "include")
  end

  it "raises invalid_config naming the key for an unknown tool, an unknown key, a bad enum value and a bad range" do
    {
      "defaults:\n  model:\n    fields: []\n" => "model",
      "defaults:\n  spec_run:\n    include_sdtout: never\n" => "include_sdtout",
      "defaults:\n  spec_run:\n    include_stdout: sometimes\n" => "include_stdout",
      "defaults:\n  spec_run:\n    timeout_seconds: 901\n" => "timeout_seconds",
      "defaults:\n  spec_run:\n    include_passing: yes please\n" => "include_passing",
      "defaults: nope\n" => "defaults"
    }.each do |yaml, key|
      File.write(File.join(@tmp, ".coatepec.yml"), yaml)

      expect { described_class.new(@tmp) }
        .to raise_error(Coatepec::Error, a_string_including(key)) { |e| expect(e.code).to eq(:invalid_config) }
    end
  end
end
