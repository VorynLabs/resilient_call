# frozen_string_literal: true

RSpec.describe ResilientCall::Storage::Memory do
  subject(:storage) { described_class.new }

  let(:state) { { status: :open, failure_count: 5, opened_at: Time.now } }

  it 'returns nil for a circuit that was never written' do
    expect(storage.read(:unknown)).to be_nil
  end

  it 'reads back exactly what was written' do
    storage.write(:stripe, state)

    expect(storage.read(:stripe)).to eq(state)
  end

  describe 'removal' do
    before do
      storage.write(:stripe, state)
      storage.write(:paypal, state)
    end

    it 'removes only the circuit passed to reset' do
      storage.reset(:stripe)

      expect(storage.read(:stripe)).to be_nil
      expect(storage.read(:paypal)).to eq(state)
    end

    it 'removes every circuit on reset_all' do
      storage.reset_all

      expect(storage.read(:stripe)).to be_nil
      expect(storage.read(:paypal)).to be_nil
    end
  end

  describe 'thread safety' do
    it 'keeps every write visible under concurrent access' do
      threads = Array.new(50) do |i|
        Thread.new { storage.write(:"circuit_#{i}", state) }
      end
      threads.each(&:join)

      50.times { |i| expect(storage.read(:"circuit_#{i}")).to eq(state) }
    end
  end
end
