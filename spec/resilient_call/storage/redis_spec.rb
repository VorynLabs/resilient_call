# frozen_string_literal: true

require 'mock_redis'

RSpec.describe ResilientCall::Storage::Redis do
  subject(:storage) { described_class.new(redis) }

  let(:redis) { MockRedis.new }
  let(:opened_at) { Time.at(1_700_000_000) }
  let(:state) do
    {
      status:               :open,
      failure_count:        5,
      opened_at:            opened_at,
      last_failure_message: 'boom',
      last_failure_class:   'RuntimeError'
    }
  end

  it 'returns nil for a circuit that was never written' do
    expect(storage.read(:unknown)).to be_nil
  end

  it 'reads back the state, restoring the symbol status and Time opened_at' do
    storage.write(:stripe, state)

    expect(storage.read(:stripe)).to eq(state)
  end

  describe 'removal' do
    before { storage.write(:stripe, state) }

    it 'deletes the circuit key on reset' do
      storage.reset(:stripe)

      expect(storage.read(:stripe)).to be_nil
      expect(redis.get('resilient_call:circuit:stripe')).to be_nil
    end

    it 'removes only the gem-prefixed keys on reset_all' do
      redis.set('unrelated:key', 'keep me')

      storage.reset_all

      expect(storage.read(:stripe)).to be_nil
      expect(redis.get('unrelated:key')).to eq('keep me')
    end
  end

  it 'shares state between two clients backed by the same Redis (two processes)' do
    process_a = described_class.new(redis)
    process_b = described_class.new(redis)

    process_a.write(:eligibility, state)

    expect(process_b.read(:eligibility)).to eq(state)
  end
end
