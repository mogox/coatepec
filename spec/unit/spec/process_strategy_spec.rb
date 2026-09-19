# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe Coatepec::Spec::ProcessStrategy do
  describe "#run when #start raises" do
    # Process.fork can fail outright (Errno::EAGAIN/ENOMEM under process-table
    # pressure), and nothing gets reaped in that case -- the pipes and tempfile
    # #run opened up front have to be released before the failure propagates.
    let(:failing_strategy_class) do
      Class.new(described_class) do
        private

        def start(_full_args, _out_w, _err_w, _json_path)
          raise Errno::EAGAIN
        end
      end
    end

    it "re-raises the original exception" do
      expect { failing_strategy_class.new(Dir.pwd).run(["spec/passing_spec.rb"], 5) }
        .to raise_error(Errno::EAGAIN)
    end

    it "closes both pipe pairs and leaves no tempfile behind" do
      pipes = []
      allow(IO).to receive(:pipe).and_wrap_original do |original|
        original.call.tap { |pair| pipes.concat(pair) }
      end

      json_path = nil
      allow(Tempfile).to receive(:create).and_wrap_original do |original, *args, &block|
        original.call(*args, &block).tap { |path| json_path = path }
      end

      expect { failing_strategy_class.new(Dir.pwd).run(["spec/passing_spec.rb"], 5) }
        .to raise_error(Errno::EAGAIN)

      expect(pipes.size).to eq(4)
      expect(pipes.map(&:closed?)).to all(be(true))
      expect(File.exist?(json_path)).to be(false)
    end
  end

  describe "#run" do
    it "stamps the subclass's execution_mode on the result" do
      stamped = Class.new(described_class) do
        def start(_args, out_w, err_w, _json_path)
          Process.spawn("true", out: out_w, err: err_w)
        end

        def execution_mode
          "stamped"
        end
      end

      result = stamped.new(Dir.pwd).run(["spec/passing_spec.rb"], 5)

      expect(result.keys.last).to eq(:execution_mode)
      expect(result[:execution_mode]).to eq("stamped")
    end

    it "requires subclasses to declare an execution_mode" do
      bare = Class.new(described_class) do
        def start(_args, out_w, err_w, _json_path)
          Process.spawn("true", out: out_w, err: err_w)
        end
      end

      expect { bare.new(Dir.pwd).run(["spec/passing_spec.rb"], 5) }.to raise_error(NotImplementedError)
    end
  end
end
