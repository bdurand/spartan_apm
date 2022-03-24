# frozen_string_literal: true

require_relative "../../spec_helper"

describe SpartanAPM::Instrumentation::HTTP do
  it "should be valid" do
    instance = SpartanAPM::Instrumentation::HTTP.new
    expect(instance.klass).to_not eq nil
    expect(instance.name).to eq :http
    expect(instance).to be_valid
  end
end
