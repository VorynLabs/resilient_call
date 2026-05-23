# frozen_string_literal: true

RSpec.describe ResilientCall do
  describe "VERSION" do
    it "is defined as a semver string" do
      expect(ResilientCall::VERSION).to be_a(String)
      expect(ResilientCall::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
    end
  end

  describe ResilientCall::CircuitOpenError do
    let(:opens_at)   { Time.now }
    let(:last_error) { RuntimeError.new("boom") }
    let(:error) do
      described_class.new(
        circuit_name: :stripe,
        opens_at:     opens_at,
        retry_after:  30,
        last_error:   last_error
      )
    end

    it "is a StandardError subclass" do
      expect(described_class.ancestors).to include(StandardError)
    end

    it "exposes the values passed to the initializer" do
      expect(error.circuit_name).to eq(:stripe)
      expect(error.opens_at).to    eq(opens_at)
      expect(error.retry_after).to eq(30)
      expect(error.last_error).to  be(last_error)
    end
  end

  describe ResilientCall::RetriesExhaustedError do
    it "is a StandardError subclass" do
      expect(described_class.ancestors).to include(StandardError)
    end

    it "exposes the attempts passed to the initializer" do
      error = described_class.new(attempts: 4)
      expect(error.attempts).to eq(4)
    end
  end

  describe ".call" do
    it "raises NotImplementedError as a placeholder" do
      expect { described_class.call { :noop } }.to raise_error(NotImplementedError)
    end
  end
end
