# frozen_string_literal: true

RSpec.describe ResilientCall do
  it "has a version number" do
    expect(ResilientCall::VERSION).not_to be nil
  end

  it "has a frozen VERSION string" do
    expect(ResilientCall::VERSION).to be_frozen
  end
end
