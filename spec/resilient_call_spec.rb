# frozen_string_literal: true

RSpec.describe ResilientCall do
  describe 'VERSION' do
    it 'is defined as a semver string' do
      expect(ResilientCall::VERSION).to be_a(String)
      expect(ResilientCall::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
    end
  end

  describe '.call (integration)' do
    # Stands in for a real external dependency wrapped by ResilientCall.call.
    let(:gateway) { double('PaymentGateway') }

    before do
      described_class.reset_configuration!
      ResilientCall::CircuitBreaker.instance_variable_set(:@registry, {})
    end

    it 'returns the value produced by the wrapped call' do
      allow(gateway).to receive(:charge).and_return(:receipt)

      expect(described_class.call { gateway.charge }).to eq(:receipt)
    end

    it 'retries and returns once the wrapped call recovers' do
      allow(gateway).to receive(:charge).and_invoke(-> { raise 'timeout' }, -> { :receipt })

      result = described_class.call(base_wait: 0) { gateway.charge }

      expect(result).to eq(:receipt)
      expect(gateway).to have_received(:charge).twice
    end

    it 'raises RetriesExhaustedError when the wrapped call never recovers' do
      allow(gateway).to receive(:charge).and_raise('timeout')

      expect { described_class.call(base_wait: 0) { gateway.charge } }
        .to raise_error(ResilientCall::RetriesExhaustedError)
    end

    it 'lets inline options override the global default' do
      allow(gateway).to receive(:charge).and_raise('timeout')

      expect { described_class.call(retries: 1, base_wait: 0) { gateway.charge } }
        .to raise_error(ResilientCall::RetriesExhaustedError)
      expect(gateway).to have_received(:charge).twice # 1 initial + 1 retry
    end

    it 'applies a profile passed via profile:' do
      described_class.define_profile(:fast, retries: 0)
      allow(gateway).to receive(:charge).and_raise('timeout')

      expect { described_class.call(profile: :fast, base_wait: 0) { gateway.charge } }
        .to raise_error(ResilientCall::RetriesExhaustedError)
      expect(gateway).to have_received(:charge).once
    end

    it 'lets an inline option override the profile' do
      described_class.define_profile(:fast, retries: 0)
      allow(gateway).to receive(:charge).and_raise('timeout')

      expect { described_class.call(profile: :fast, retries: 2, base_wait: 0) { gateway.charge } }
        .to raise_error(ResilientCall::RetriesExhaustedError)
      expect(gateway).to have_received(:charge).exactly(3).times # inline retries: 2 wins
    end

    it 'changes subsequent calls after configure' do
      described_class.configure { |c| c.retries = 0 }
      allow(gateway).to receive(:charge).and_raise('timeout')

      expect { described_class.call(base_wait: 0) { gateway.charge } }
        .to raise_error(ResilientCall::RetriesExhaustedError)
      expect(gateway).to have_received(:charge).once
    end

    it 'restores defaults on reset_configuration!' do
      described_class.configure { |c| c.retries = 0 }
      described_class.reset_configuration!
      allow(gateway).to receive(:charge).and_raise('timeout')

      expect { described_class.call(base_wait: 0) { gateway.charge } }
        .to raise_error(ResilientCall::RetriesExhaustedError)
      expect(gateway).to have_received(:charge).exactly(4).times # default retries: 3 + initial
    end

    context 'when the circuit is already open' do
      before do
        allow(gateway).to receive(:charge).and_raise('timeout')

        expect { described_class.call(circuit: :pay, threshold: 1, retries: 0) { gateway.charge } }
          .to raise_error(ResilientCall::RetriesExhaustedError)
      end

      it 'runs the fallback instead of the wrapped call' do
        result = described_class.call(circuit: :pay, threshold: 1, retries: 0, fallback: -> { :cached }) do
          gateway.charge
        end

        expect(result).to eq(:cached)
      end

      it 'raises CircuitOpenError when no fallback is set' do
        expect { described_class.call(circuit: :pay, threshold: 1, retries: 0) { gateway.charge } }
          .to raise_error(ResilientCall::CircuitOpenError)
      end
    end
  end
end
