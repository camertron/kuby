# typed: false

require 'spec_helper'

describe Kuby::TrailingHash do
  it 'allows adding new entries during iteration' do
    h = { a: 'b', b: 'c' }
    th = described_class[:a, 'b', :b, 'c']
    seen_keys = []

    # regular hashes don't allow adding keys during iteration
    expect do
      h.each_with_index do |(_k, _), idx|
        h[:c] = 'd' if idx == 0
      end
    end.to raise_error(RuntimeError)

    th.each_with_index do |(k, _), idx|
      th[:c] = 'd' if idx == 0
      seen_keys << k
    end

    expect(seen_keys).to eq(%i[a b c])
  end
end
