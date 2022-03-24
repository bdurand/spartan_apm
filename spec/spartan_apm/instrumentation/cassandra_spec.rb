# frozen_string_literal: true

require_relative "../../spec_helper"

describe SpartanAPM::Instrumentation::Cassandra do
  it "should be valid" do
    instance = SpartanAPM::Instrumentation::Cassandra.new
    expect(instance.klass).to_not eq nil
    expect(instance.name).to eq :cassandra
    expect(instance).to be_valid
  end
end
