# frozen_string_literal: true

require "spec_helper"

RSpec.describe Coatepec::Worker::Client do
  # These examples construct a Client without going through .spawn (which
  # execs the real coatepec-worker binary under a target app's bundle) --
  # #alive? only ever touches @pid, so a bare instance with @pid set by
  # hand is enough to exercise it in isolation, no Rails boot required.
  subject(:client) { described_class.allocate }

  describe "#alive? (stubbed Process, unit-level)" do
    it "returns false without checking Process.kill when the pid has already exited" do
      client.instance_variable_set(:@pid, 4242)
      allow(Process).to receive(:waitpid2)
        .with(4242, Process::WNOHANG).and_return([4242, instance_double(Process::Status)])
      allow(Process).to receive(:kill)

      expect(client.alive?).to be(false)
      expect(Process).not_to have_received(:kill)
    end

    it "returns true when the pid is still running" do
      client.instance_variable_set(:@pid, 4242)
      allow(Process).to receive(:waitpid2).with(4242, Process::WNOHANG).and_return(nil)
      allow(Process).to receive(:kill).with(0, 4242)

      expect(client.alive?).to be(true)
    end

    it "returns false when Process.kill raises Errno::ESRCH" do
      client.instance_variable_set(:@pid, 4242)
      allow(Process).to receive(:waitpid2).with(4242, Process::WNOHANG).and_return(nil)
      allow(Process).to receive(:kill).with(0, 4242).and_raise(Errno::ESRCH)

      expect(client.alive?).to be(false)
    end

    it "returns false immediately when there is no pid at all" do
      expect(client.alive?).to be(false)
    end
  end

  describe "#alive? (real process, unit-level)" do
    it "reaps a genuinely exited child rather than leaving it a zombie" do
      pid = Process.spawn("true", out: File::NULL, err: File::NULL)
      client.instance_variable_set(:@pid, pid)

      # "true" exits almost immediately, but not synchronously with spawn --
      # poll #alive? itself (the method under test) until it catches up,
      # bounded so a real regression (never noticing the exit) fails the
      # test instead of hanging it.
      deadline = Time.now + 2
      alive = true
      alive = client.alive? while alive && Time.now < deadline

      expect(alive).to be(false)
      expect { Process.wait(pid) }.to raise_error(Errno::ECHILD)
    end
  end
end
