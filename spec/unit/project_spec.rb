# frozen_string_literal: true

require "spec_helper"
require "coatepec/project"
require "tmpdir"
require "fileutils"

RSpec.describe Coatepec::Project do
  around do |example|
    Dir.mktmpdir do |dir|
      @tmp = dir
      example.run
    end
  end

  it "expands and accepts a root that has a Gemfile" do
    File.write(File.join(@tmp, "Gemfile"), "source 'https://rubygems.org'\n")

    project = described_class.new(@tmp)

    expect(project.root).to eq(File.expand_path(@tmp))
  end

  it "raises project_not_found when there is no Gemfile" do
    expect { described_class.new(@tmp) }
      .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:project_not_found) }
  end

  it "lists spec, packs/*/spec, engines/*/spec, and gems/*/spec that exist" do
    File.write(File.join(@tmp, "Gemfile"), "source 'https://rubygems.org'\n")
    FileUtils.mkdir_p(File.join(@tmp, "spec"))
    FileUtils.mkdir_p(File.join(@tmp, "packs/schools/spec"))
    FileUtils.mkdir_p(File.join(@tmp, "packs/schools/lib")) # not a spec dir, should be excluded

    project = described_class.new(@tmp)

    expect(project.spec_root_candidates).to contain_exactly(
      File.join(File.expand_path(@tmp), "spec"),
      File.join(File.expand_path(@tmp), "packs/schools/spec")
    )
  end

  it "exposes a memoized ProjectConfig rooted at the project root" do
    File.write(File.join(@tmp, "Gemfile"), "source 'https://rubygems.org'\n")
    File.write(File.join(@tmp, ".coatepec.yml"), "macos_fork: true\n")

    project = described_class.new(@tmp)

    expect(project.config).to be_a(Coatepec::ProjectConfig)
    expect(project.config.macos_fork?).to be(true)
    expect(project.config).to equal(project.config)
  end
end
