# frozen_string_literal: true

require_relative "../spec_helper"

describe SpartanAPM::StringCache do
  it "should return a frozen cached version of a string" do
    cache = SpartanAPM::StringCache.new
    expect(cache.fetch(nil)).to eq nil
    foo = cache.fetch(+"foo")
    expect(foo).to eq "foo"
    expect(foo.frozen?).to eq true
    expect(cache.fetch(:foo).object_id).to eq foo.object_id
    expect(cache.fetch("bar")).to eq "bar"
  end
end
