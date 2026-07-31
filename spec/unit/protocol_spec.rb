# frozen_string_literal: true

require "spec_helper"
require "coatepec/protocol"
require "stringio"

RSpec.describe Coatepec::Protocol do
  it "writes one newline-terminated JSON message per call" do
    output = StringIO.new
    protocol = described_class.new(input: StringIO.new, output: output)

    protocol.write(id: 1, command: "status")

    expect(output.string).to eq(%({"id":1,"command":"status"}\n))
  end

  it "reads a JSON line with symbolized keys" do
    input = StringIO.new(%({"id":1,"ok":true,"data":{"pid":123}}\n))
    protocol = described_class.new(input: input, output: StringIO.new)

    expect(protocol.read).to eq(id: 1, ok: true, data: { pid: 123 })
  end

  it "returns nil at EOF" do
    protocol = described_class.new(input: StringIO.new, output: StringIO.new)

    expect(protocol.read).to be_nil
  end

  it "raises FramingError on malformed JSON" do
    input = StringIO.new("not json\n")
    protocol = described_class.new(input: input, output: StringIO.new)

    expect { protocol.read }.to raise_error(Coatepec::Protocol::FramingError)
  end
end
