# frozen_string_literal: true

require_relative "../../spec_helper"

describe SpartanAPM::Instrumentation::Bunny do
  it "should be valid" do
    instance = SpartanAPM::Instrumentation::Bunny.new
    expect(instance.klass).to_not eq nil
    expect(instance.name).to eq :rabbitmq
    expect(instance).to be_valid
  end
end
