# frozen_string_literal: true

RSpec.describe ResilientCall::Circuit do
  subject(:circuit) { described_class.new(:stripe, threshold: 3, reset_timeout: 30) }

  let(:error) { RuntimeError.new('boom') }
  let(:now) { Time.now }

  before { allow(Time).to receive(:now).and_return(now) }

  describe 'initial state' do
    it 'is :closed' do
      expect(circuit.state).to eq(:closed)
    end

    it 'allows requests' do
      expect(circuit.allow_request?).to be(true)
    end
  end

  describe 'when failures reach the threshold' do
    before { circuit.threshold.times { circuit.record_failure!(error) } }

    it 'opens the circuit' do
      expect(circuit.state).to eq(:open)
    end

    it 'records opened_at' do
      expect(circuit.opened_at).to eq(now)
    end

    it 'blocks requests while the reset_timeout has not elapsed' do
      expect(circuit.allow_request?).to be(false)
    end

    describe 'after the reset_timeout elapses' do
      let(:later) { now + circuit.reset_timeout + 1 }

      before { allow(Time).to receive(:now).and_return(later) }

      it 'lets a probe through and moves to :half_open' do
        expect(circuit.allow_request?).to be(true)
        expect(circuit.state).to eq(:half_open)
      end

      describe 'and the circuit is probed (:half_open)' do
        before { circuit.allow_request? }

        it 'closes again on a successful probe' do
          circuit.record_success!

          expect(circuit.state).to eq(:closed)
          expect(circuit.failure_count).to eq(0)
        end

        it 'reopens on a failed probe and restarts opened_at' do
          circuit.record_failure!(error)

          expect(circuit.state).to eq(:open)
          expect(circuit.opened_at).to eq(later)
        end
      end
    end
  end

  describe '#reset!' do
    before do
      circuit.threshold.times { circuit.record_failure!(error) }
      circuit.reset!
    end

    it 'forces :closed and zeros every counter' do
      expect(circuit.state).to eq(:closed)
      expect(circuit.failure_count).to eq(0)
      expect(circuit.opened_at).to be_nil
      expect(circuit.last_failure).to be_nil
    end
  end

  describe 'thread safety' do
    subject(:circuit) { described_class.new(:concurrent, threshold: 1_000, reset_timeout: 30) }

    it 'keeps failure_count exact under concurrent record_failure! calls' do
      threads = Array.new(50) { Thread.new { circuit.record_failure!(error) } }
      threads.each(&:join)

      expect(circuit.failure_count).to eq(50)
    end
  end
end
