# frozen_string_literal: true

RSpec.describe ResilientCall::Retrier do
  subject(:retrier) { described_class.new(options) }

  let(:options) { {} }
  let(:work)    { double('work') }
  let(:error)   { RuntimeError.new('boom') }

  # Never sleep for real time; stubbing also lets us inspect the wait values.
  before { allow(retrier).to receive(:sleep) }

  describe '#call' do
    context 'when the block succeeds on the first attempt' do
      let(:options)    { { on_success: on_success } }
      let(:on_success) { double('on_success', call: nil) }

      before { allow(work).to receive(:call).and_return(:ok) }

      it 'returns the block result' do
        expect(retrier.call { work.call }).to eq(:ok)
      end

      it 'invokes the block once' do
        retrier.call { work.call }
        expect(work).to have_received(:call).once
      end

      it 'never sleeps' do
        retrier.call { work.call }
        expect(retrier).not_to have_received(:sleep)
      end

      it 'fires on_success with the result and the attempt number' do
        retrier.call { work.call }
        expect(on_success).to have_received(:call).with(:ok, 1)
      end
    end

    context 'when the block succeeds on an intermediate attempt' do
      let(:options) { { retries: 3 } }

      before do
        allow(work).to receive(:call).and_invoke(
          -> { raise error },
          -> { raise error },
          -> { :ok }
        )
      end

      it 'returns the eventual result' do
        expect(retrier.call { work.call }).to eq(:ok)
      end

      it 'invokes the block until it succeeds' do
        retrier.call { work.call }
        expect(work).to have_received(:call).exactly(3).times
      end

      it 'sleeps before each retry' do
        retrier.call { work.call }
        expect(retrier).to have_received(:sleep).twice
      end
    end

    context 'when every attempt fails' do
      let(:options) { { retries: 2 } }

      before { allow(work).to receive(:call).and_raise(error) }

      it 'raises RetriesExhaustedError' do
        expect { retrier.call { work.call } }
          .to raise_error(ResilientCall::RetriesExhaustedError)
      end

      it 'reports the total number of attempts' do
        expect { retrier.call { work.call } }
          .to raise_error(ResilientCall::RetriesExhaustedError) do |e|
            expect(e.attempts).to eq(3) # 1 initial + 2 retries
          end
      end

      it 'exposes the last captured exception via #cause' do
        expect { retrier.call { work.call } }
          .to raise_error(ResilientCall::RetriesExhaustedError) do |e|
            expect(e.cause).to be(error)
          end
      end
    end

    context 'when the error is not listed in :on' do
      let(:options) { { retries: 5, on: [KeyError] } }

      before { allow(work).to receive(:call).and_raise(ArgumentError, 'not retried') }

      it 'propagates the original error' do
        expect { retrier.call { work.call } }.to raise_error(ArgumentError)
      end

      it 'does not retry' do
        expect { retrier.call { work.call } }.to raise_error(ArgumentError)
        expect(work).to have_received(:call).once
      end
    end
  end

  describe 'backoff' do
    before do
      allow(work).to receive(:call).and_raise(error)
      expect { retrier.call { work.call } }
        .to raise_error(ResilientCall::RetriesExhaustedError)
    end

    context 'with :exponential strategy' do
      let(:options) { { retries: 3, wait: :exponential, base_wait: 0.5, jitter: false } }

      it 'doubles the wait each attempt' do
        expect(retrier).to have_received(:sleep).with(1.0).ordered
        expect(retrier).to have_received(:sleep).with(2.0).ordered
        expect(retrier).to have_received(:sleep).with(4.0).ordered
      end
    end

    context 'with :linear strategy' do
      let(:options) { { retries: 3, wait: :linear, base_wait: 0.5, jitter: false } }

      it 'grows the wait by base_wait each attempt' do
        expect(retrier).to have_received(:sleep).with(0.5).ordered
        expect(retrier).to have_received(:sleep).with(1.0).ordered
        expect(retrier).to have_received(:sleep).with(1.5).ordered
      end
    end

    context 'with :fixed strategy' do
      let(:options) { { retries: 3, wait: :fixed, base_wait: 0.5, jitter: false } }

      it 'keeps the wait constant' do
        expect(retrier).to have_received(:sleep).with(0.5).exactly(3).times
      end
    end

    context 'with a custom lambda strategy' do
      let(:options) { { retries: 3, wait: ->(n) { n * 1.5 }, jitter: false } }

      it 'calls the lambda with the 1-based attempt number' do
        expect(retrier).to have_received(:sleep).with(1.5).ordered
        expect(retrier).to have_received(:sleep).with(3.0).ordered
        expect(retrier).to have_received(:sleep).with(4.5).ordered
      end
    end

    context 'when the wait exceeds max_wait' do
      let(:options) { { retries: 4, wait: :exponential, base_wait: 1.0, max_wait: 3.0, jitter: false } }

      it 'caps every wait at max_wait' do
        expect(retrier).to have_received(:sleep).with(2.0).ordered
        expect(retrier).to have_received(:sleep).with(3.0).exactly(3).times
      end
    end

    context 'when jitter is enabled' do
      let(:options) { { retries: 1, wait: :fixed, base_wait: 0.5, jitter: true } }

      it 'adds positive variation to the wait' do
        expect(retrier).to have_received(:sleep).with(a_value >= 0.5)
      end
    end
  end

  describe 'callbacks' do
    context 'on_retry' do
      let(:options)  { { retries: 2, on_retry: on_retry } }
      let(:on_retry) { double('on_retry', call: nil) }

      before do
        allow(work).to receive(:call).and_raise(error)
        expect { retrier.call { work.call } }
          .to raise_error(ResilientCall::RetriesExhaustedError)
      end

      it 'fires with the attempt number and exception on each retry' do
        expect(on_retry).to have_received(:call).with(1, error).ordered
        expect(on_retry).to have_received(:call).with(2, error).ordered
      end
    end

    context 'on_failure' do
      let(:options)    { { retries: 1, on_failure: on_failure } }
      let(:on_failure) { double('on_failure', call: nil) }

      before do
        allow(work).to receive(:call).and_raise(error)
        expect { retrier.call { work.call } }
          .to raise_error(ResilientCall::RetriesExhaustedError)
      end

      it 'fires once with the final exception' do
        expect(on_failure).to have_received(:call).with(error).once
      end
    end

    context 'on_success' do
      let(:options)    { { retries: 3, on_success: on_success } }
      let(:on_success) { double('on_success', call: nil) }

      before do
        allow(work).to receive(:call).and_invoke(
          -> { raise error },
          -> { raise error },
          -> { :done }
        )
      end

      it 'fires with the result and the total attempt count' do
        retrier.call { work.call }
        expect(on_success).to have_received(:call).with(:done, 3)
      end
    end
  end
end
