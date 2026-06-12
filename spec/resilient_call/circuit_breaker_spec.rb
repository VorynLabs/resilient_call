# frozen_string_literal: true

RSpec.describe ResilientCall::CircuitBreaker do
  before do
    described_class.instance_variable_set(:@registry, {})
  end

  it 'returns the same instance for the same name' do
    expect(described_class[:stripe]).to be(described_class[:stripe])
  end

  it 'returns independent instances for different names' do
    expect(described_class[:a]).not_to be(described_class[:b])
  end

  it 'resets every registered circuit on reset_all!' do
    expect(described_class[:a]).to receive(:reset!)
    expect(described_class[:b]).to receive(:reset!)

    described_class.reset_all!
  end
end
