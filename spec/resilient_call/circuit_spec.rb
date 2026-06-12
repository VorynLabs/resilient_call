# frozen_string_literal: true

RSpec.describe ResilientCall::Circuit do
  subject(:circuit) { described_class.new(:stripe, threshold: 3, reset_timeout: 30) }

  let(:error) { RuntimeError.new("boom") }

  def trip!(times = 3)
    times.times { circuit.record_failure!(error) }
  end

  it "starts in the :closed state" do
    expect(circuit.state).to eq(:closed)
  end

  it "allows requests while :closed" do
    expect(circuit.allow_request?).to be(true)
  end

  it "opens after threshold consecutive failures" do
    trip!(3)
    expect(circuit.state).to eq(:open)
  end

  it "records opened_at when it opens" do
    trip!(3)
    expect(circuit.opened_at).to be_a(Time)
  end

  it "blocks requests while :open and the reset_timeout has not elapsed" do
    trip!(3)
    expect(circuit.allow_request?).to be(false)
  end

  it "transitions to :half_open once the reset_timeout elapses" do
    opened = Time.now
    allow(Time).to receive(:now).and_return(opened)
    trip!(3)

    allow(Time).to receive(:now).and_return(opened + 31)
    expect(circuit.allow_request?).to be(true)
    expect(circuit.state).to eq(:half_open)
  end

  it "closes again on record_success! while :half_open" do
    opened = Time.now
    allow(Time).to receive(:now).and_return(opened)
    trip!(3)
    allow(Time).to receive(:now).and_return(opened + 31)
    circuit.allow_request? # moves to :half_open

    circuit.record_success!
    expect(circuit.state).to eq(:closed)
    expect(circuit.failure_count).to eq(0)
  end

  it "reopens on record_failure! while :half_open and restarts opened_at" do
    opened = Time.now
    allow(Time).to receive(:now).and_return(opened)
    trip!(3)
    allow(Time).to receive(:now).and_return(opened + 31)
    circuit.allow_request? # moves to :half_open

    reopened = opened + 31
    allow(Time).to receive(:now).and_return(reopened)
    circuit.record_failure!(error)
    expect(circuit.state).to eq(:open)
    expect(circuit.opened_at).to eq(reopened)
  end

  it "forces :closed and zeros every counter on reset!" do
    trip!(3)
    circuit.reset!
    expect(circuit.state).to eq(:closed)
    expect(circuit.failure_count).to eq(0)
    expect(circuit.opened_at).to be_nil
    expect(circuit.last_failure).to be_nil
  end

  it "is thread-safe under concurrent record_failure! calls" do
    big = described_class.new(:concurrent, threshold: 1_000, reset_timeout: 30)
    threads = Array.new(50) do
      Thread.new { big.record_failure!(error) }
    end
    threads.each(&:join)
    expect(big.failure_count).to eq(50)
  end
end
