# frozen_string_literal: true

require_relative "../../spec_helper"

describe SpartanAPM::Web::Helpers, freeze_time: true do
  let(:end_time) { SpartanAPM.bucket_time(SpartanAPM.bucket(Time.now)) }
  let(:start_time) { end_time - 120 }
  let(:bucket_1) { SpartanAPM.bucket(start_time) }
  let(:bucket_2) { SpartanAPM.bucket(start_time + 60) }
  let(:bucket_3) { SpartanAPM.bucket(start_time + 120) }
  let(:app) { "app" }
  let(:persistence) { SpartanAPM::Persistence.new(app) }

  let(:measures_1) do
    sample_measures({
      "action_1" => [10, 20, 30, 40, 50],
      "action_2" => [15, 25, 35],
      "action_3" => [50, 60, 70],
      "errors" => [ArgumentError.new, StandardError.new]
    })
  end

  let(:measures_2) do
    sample_measures({
      "action_1" => [20, 30, 40, 50, 60],
      "action_2" => [25, 35, 45]
    })
  end

  let(:measures_3) do
    sample_measures({
      "action_1" => [10, 20, 30, 40, 50, 60, 70],
      "action_2" => [15, 25, 35, 45, 55],
      "errors" => [ArgumentError.new, StandardError.new, ArgumentError.new]
    })
  end

  let(:measures_4) do
    sample_measures({
      "action_1" => [10, 20, 30, 40],
      "action_2" => [15, 25, 35, 45],
      "action_4" => [30, 50, 60]
    })
  end

  def sample_measures(action_times)
    measures = []
    errors = Array(action_times["errors"]).dup
    action_times.each do |action, times|
      next if action == "errors"
      times.each do |value|
        measure = SpartanAPM::Measure.new(app, action)
        measures << measure
        measure.timers["app"] = (value.to_f * 2) / 1000.0
        measure.counts["app"] = 1
        measure.timers["database"] = value.to_f / 1000.0
        measure.counts["database"] = 2
        measure.error = errors.pop
      end
    end
    measures
  end

  before do
    allow(SpartanAPM).to receive(:host).and_return("host_1")
    SpartanAPM::Persistence.store!(bucket_1, measures_1)
    SpartanAPM::Persistence.store!(bucket_2, measures_2)
    SpartanAPM::Persistence.store!(bucket_3, measures_3)
    allow(SpartanAPM).to receive(:host).and_return("host_2")
    SpartanAPM::Persistence.store!(bucket_1, measures_4)
  end

  after do
    persistence.clear!([start_time, end_time])
  end

  it "should render a metrics response"

  it "should render a live metrics response"

  it "should render an actions response"

  it "should render an errors response"
end
