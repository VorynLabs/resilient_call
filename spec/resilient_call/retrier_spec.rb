# frozen_string_literal: true

RSpec.describe ResilientCall::Retrier do
  # Never sleep for real time in specs.
  def build(options = {})
    described_class.new(options).tap do |retrier|
      allow(retrier).to receive(:sleep)
    end
  end

  # A block that fails `n` times with `error`, then returns `result`.
  def flaky(n, error: RuntimeError.new("boom"), result: :ok)
    calls = 0
    lambda do
      calls += 1
      raise error if calls <= n

      result
    end
  end

  describe "#call" do
    it "returns the block result when it succeeds on the first attempt" do
      retrier = build
      expect(retrier.call { :ok }).to eq(:ok)
    end

    it "retries and returns the result when it succeeds on an intermediate attempt" do
      retrier = build(retries: 3)
      expect(retrier.call(&flaky(2))).to eq(:ok)
    end

    it "raises RetriesExhaustedError once every attempt is consumed" do
      retrier = build(retries: 2)
      expect { retrier.call { raise "boom" } }
        .to raise_error(ResilientCall::RetriesExhaustedError)
    end

    it "reports the correct number of attempts on RetriesExhaustedError" do
      retrier = build(retries: 2)
      retrier.call { raise "boom" }
    rescue ResilientCall::RetriesExhaustedError => e
      expect(e.attempts).to eq(3) # 1 initial + 2 retries
    end

    it "exposes the last captured exception via #cause" do
      boom = ArgumentError.new("last one")
      retrier = build(retries: 1)
      retrier.call { raise boom }
    rescue ResilientCall::RetriesExhaustedError => e
      expect(e.cause).to be(boom)
    end

    it "only retries exceptions listed in :on, propagating others immediately" do
      retrier = build(retries: 5, on: [KeyError])
      calls = 0
      block = lambda do
        calls += 1
        raise ArgumentError, "not retried"
      end

      expect { retrier.call(&block) }.to raise_error(ArgumentError)
      expect(calls).to eq(1)
    end
  end

  describe "backoff" do
    def waits_for(options)
      retrier = build(options.merge(jitter: false))
      slept = []
      allow(retrier).to receive(:sleep) { |s| slept << s }
      begin
        retrier.call { raise "boom" }
      rescue ResilientCall::RetriesExhaustedError
        # ignore — we only care about the sleep arguments
      end
      slept
    end

    it "computes :exponential backoff per attempt" do
      expect(waits_for(retries: 3, wait: :exponential, base_wait: 0.5))
        .to eq([1.0, 2.0, 4.0])
    end

    it "computes :linear backoff per attempt" do
      expect(waits_for(retries: 3, wait: :linear, base_wait: 0.5))
        .to eq([0.5, 1.0, 1.5])
    end

    it "keeps :fixed backoff constant between attempts" do
      expect(waits_for(retries: 3, wait: :fixed, base_wait: 0.5))
        .to eq([0.5, 0.5, 0.5])
    end

    it "calls a custom lambda with the 1-based attempt number" do
      expect(waits_for(retries: 3, wait: ->(n) { n * 1.5 }, base_wait: 0.5))
        .to eq([1.5, 3.0, 4.5])
    end

    it "caps the backoff at max_wait" do
      slept = waits_for(retries: 4, wait: :exponential, base_wait: 1.0, max_wait: 3.0)
      expect(slept).to all(be <= 3.0)
      expect(slept).to eq([2.0, 3.0, 3.0, 3.0])
    end

    it "adds positive variation when jitter is enabled" do
      retrier = build(retries: 1, wait: :fixed, base_wait: 0.5, jitter: true)
      slept = []
      allow(retrier).to receive(:sleep) { |s| slept << s }
      begin
        retrier.call { raise "boom" }
      rescue ResilientCall::RetriesExhaustedError
        nil
      end
      expect(slept.first).to be >= 0.5
    end
  end

  describe "callbacks" do
    it "calls on_retry with attempt and exception on each retry" do
      seen = []
      retrier = build(retries: 2, on_retry: ->(attempt, err) { seen << [attempt, err.message] })
      begin
        retrier.call { raise "boom" }
      rescue ResilientCall::RetriesExhaustedError
        nil
      end
      expect(seen).to eq([[1, "boom"], [2, "boom"]])
    end

    it "calls on_failure with the exception once attempts are exhausted" do
      captured = nil
      retrier = build(retries: 1, on_failure: ->(err) { captured = err })
      begin
        retrier.call { raise "boom" }
      rescue ResilientCall::RetriesExhaustedError
        nil
      end
      expect(captured).to be_a(RuntimeError)
      expect(captured.message).to eq("boom")
    end

    it "calls on_success with the result and the attempt count" do
      captured = nil
      retrier = build(retries: 3, on_success: ->(result, attempts) { captured = [result, attempts] })
      retrier.call(&flaky(2, result: :done))
      expect(captured).to eq([:done, 3])
    end
  end
end
