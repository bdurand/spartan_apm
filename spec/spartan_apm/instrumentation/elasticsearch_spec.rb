# frozen_string_literal: true

require_relative "../../spec_helper"

describe SpartanAPM::Instrumentation::Elasticsearch do
  it "should be valid" do
    instance = SpartanAPM::Instrumentation::Elasticsearch.new
    expect(instance.klass).to_not eq nil
    expect(instance.name).to eq :elasticsearch
    expect(instance).to be_valid
  end
end
