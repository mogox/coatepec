# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe "fixture_db_needs_reload?" do
  around do |example|
    Dir.mktmpdir do |dir|
      @tmp = dir
      example.run
    end
  end

  def touch(path, at:)
    File.write(path, "x")
    File.utime(at, at, path)
  end

  it "is true when the database file doesn't exist" do
    schema_path = File.join(@tmp, "schema.rb")
    touch(schema_path, at: Time.now)

    expect(fixture_db_needs_reload?(File.join(@tmp, "missing.sqlite3"), schema_path)).to be(true)
  end

  it "is true when schema.rb is newer than the database file" do
    db_path = File.join(@tmp, "test.sqlite3")
    schema_path = File.join(@tmp, "schema.rb")
    touch(db_path, at: Time.now)
    touch(schema_path, at: Time.now + 60)

    expect(fixture_db_needs_reload?(db_path, schema_path)).to be(true)
  end

  it "is false when the database file is newer than schema.rb" do
    schema_path = File.join(@tmp, "schema.rb")
    db_path = File.join(@tmp, "test.sqlite3")
    touch(schema_path, at: Time.now)
    touch(db_path, at: Time.now + 60)

    expect(fixture_db_needs_reload?(db_path, schema_path)).to be(false)
  end
end
