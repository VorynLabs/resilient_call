# frozen_string_literal: true

RSpec.describe ResilientCall::Mixin do
  # Smallest possible host: wraps a method that runs the block it receives, so
  # the block passed in each example IS the body under retry. The unit under
  # test is the wrapping, not a particular service.
  let(:host) do
    Class.new do
      include ResilientCall::Mixin

      def run(*args, **kwargs, &block)
        block.call(*args, **kwargs)
      end
      resilient_method :run, retries: 2, base_wait: 0
    end
  end

  let(:instance) { host.new }

  before do
    ResilientCall.reset_configuration!
    ResilientCall::CircuitBreaker.instance_variable_set(:@registry, {})
  end

  it 'routes the call through ResilientCall.call with the declared options' do
    expect(ResilientCall).to receive(:call).with(retries: 2, base_wait: 0).and_call_original

    instance.run { :ok }
  end

  it 'forwards positional and keyword arguments to the wrapped block' do
    result = instance.run(10, currency: :usd) { |amount, currency:| [amount, currency] }

    expect(result).to eq([10, :usd])
  end

  it 'runs the passed block and returns its result' do
    expect(instance.run { :from_block }).to eq(:from_block)
  end

  it 'runs the block again on failure until it recovers' do
    outcomes = [-> { raise 'timeout' }, -> { :ok }]

    expect(instance.run { outcomes.shift.call }).to eq(:ok)
    expect(outcomes).to be_empty
  end

  it 'surfaces RetriesExhaustedError when the block keeps failing' do
    expect { instance.run { raise 'timeout' } }
      .to raise_error(ResilientCall::RetriesExhaustedError)
  end
end
