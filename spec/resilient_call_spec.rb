# frozen_string_literal: true

RSpec.describe ResilientCall do
  describe 'VERSION' do
    it 'is defined as a semver string' do
      expect(ResilientCall::VERSION).to be_a(String)
      expect(ResilientCall::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
    end
  end

  describe ResilientCall::CircuitOpenError do
    let(:opens_at)   { Time.now }
    let(:last_error) { RuntimeError.new('boom') }
    let(:error) do
      described_class.new(
        circuit_name: :stripe,
        opens_at:     opens_at,
        retry_after:  30,
        last_error:   last_error
      )
    end

    it 'is a StandardError subclass' do
      expect(described_class.ancestors).to include(StandardError)
    end

    it 'exposes the values passed to the initializer' do
      expect(error.circuit_name).to eq(:stripe)
      expect(error.opens_at).to    eq(opens_at)
      expect(error.retry_after).to eq(30)
      expect(error.last_error).to  be(last_error)
    end
  end

  describe ResilientCall::RetriesExhaustedError do
    it 'is a StandardError subclass' do
      expect(described_class.ancestors).to include(StandardError)
    end

    it 'exposes the attempts passed to the initializer' do
      error = described_class.new(attempts: 4)
      expect(error.attempts).to eq(4)
    end
  end

  describe '.call (integration)' do
    before(:each) do
      described_class.reset_configuration!
      ResilientCall::CircuitBreaker.instance_variable_set(:@registry, {})
    end

    # Counts how many times the block runs while raising every time.
    def always_failing
      calls = 0
      block = lambda do
        calls += 1
        raise 'boom'
      end
      [block, -> { calls }]
    end

    it 'returns the block result for a simple call' do
      expect(described_class.call { :ok }).to eq(:ok)
    end

    it 'retries and returns the result when the block succeeds on the second attempt' do
      calls = 0
      result = described_class.call(base_wait: 0) do
        calls += 1
        raise 'boom' if calls < 2

        :ok
      end

      expect(result).to eq(:ok)
      expect(calls).to eq(2)
    end

    it 'raises RetriesExhaustedError once attempts are exhausted' do
      expect { described_class.call(base_wait: 0) { raise 'boom' } }
        .to raise_error(ResilientCall::RetriesExhaustedError)
    end

    it 'lets inline options override the global default' do
      block, count = always_failing
      described_class.call(retries: 1, base_wait: 0, &block) rescue nil
      expect(count.call).to eq(2) # 1 initial + 1 retry
    end

    it 'applies a profile passed via profile:' do
      described_class.define_profile(:fast, retries: 0)
      block, count = always_failing
      described_class.call(profile: :fast, base_wait: 0, &block) rescue nil
      expect(count.call).to eq(1)
    end

    it 'lets an inline option override the profile' do
      described_class.define_profile(:fast, retries: 0)
      block, count = always_failing
      described_class.call(profile: :fast, retries: 2, base_wait: 0, &block) rescue nil
      expect(count.call).to eq(3) # inline retries: 2 wins
    end

    it 'runs the fallback when the circuit is open' do
      described_class.call(circuit: :pay, threshold: 1, retries: 0) { raise 'boom' } rescue nil

      result = described_class.call(circuit: :pay, threshold: 1, retries: 0, fallback: -> { :cached }) do
        raise 'should not run'
      end

      expect(result).to eq(:cached)
    end

    it 'raises CircuitOpenError when the circuit is open and no fallback is set' do
      described_class.call(circuit: :pay, threshold: 1, retries: 0) { raise 'boom' } rescue nil

      expect { described_class.call(circuit: :pay, threshold: 1, retries: 0) { :noop } }
        .to raise_error(ResilientCall::CircuitOpenError)
    end

    it 'changes subsequent calls after configure' do
      described_class.configure { |c| c.retries = 0 }
      block, count = always_failing
      described_class.call(base_wait: 0, &block) rescue nil
      expect(count.call).to eq(1)
    end

    it 'restores defaults on reset_configuration!' do
      described_class.configure { |c| c.retries = 0 }
      described_class.reset_configuration!
      block, count = always_failing
      described_class.call(base_wait: 0, &block) rescue nil
      expect(count.call).to eq(4) # default retries: 3 + initial
    end
  end
end
