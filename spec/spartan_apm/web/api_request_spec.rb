# frozen_string_literal: true

require_relative "../../spec_helper"

describe SpartanAPM::Web::ApiRequest, freeze_time: true do
  let(:rack_request) { Rack::Request.new({}).tap { |r| r.update_param("app", "app") } }

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
        measure.capture_error(errors.pop)
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

  describe "metrics" do
    it "should render a metrics response" do
      request = SpartanAPM::Web::ApiRequest.new(rack_request)
      response = request.metrics
      expect(response[:env]).to eq "test"
      expect(response[:app]).to eq "app"
      expect(response).to include(:host)
      expect(response).to include(:action)
      expect(response[:hosts]).to eq ["host_1", "host_2"]
      expect(response[:actions]).to eq ["action_1", "action_2", "action_3", "action_4"]
      expect(response[:minutes]).to eq 30
      expect(response[:interval_minutes]).to eq 1
      expect(response[:times]).to include(SpartanAPM.bucket_time(SpartanAPM.bucket(Time.now - 1800)).iso8601)
      expect(response).to include(:avg)
      expect(response).to include(:p50)
      expect(response).to include(:p90)
      expect(response).to include(:p99)
      expect(response).to include(:throughput)
      expect(response).to include(:errors)
      expect(response).to include(:error_rate)
    end

    it "should filter metrics by host" do
      rack_request.update_param("host", "host_1")
      request = SpartanAPM::Web::ApiRequest.new(rack_request)
      response = request.metrics
      expect(response[:host]).to eq "host_1"
      expect(response[:hosts]).to eq ["host_1"]
    end

    it "should filter metrics by action" do
      rack_request.update_param("action", "action_1")
      request = SpartanAPM::Web::ApiRequest.new(rack_request)
      response = request.metrics
      expect(response[:action]).to eq "action_1"
      expect(response[:actions]).to eq ["action_1", "action_2", "action_3", "action_4"]
    end

    it "should set a time range for metrics" do
      rack_request.update_param("minutes", "3600")
      request = SpartanAPM::Web::ApiRequest.new(rack_request)
      response = request.metrics
      expect(response[:minutes]).to eq 3600
      expect(response[:interval_minutes]).to eq 60
    end
  end

  describe "live_metrics" do
    it "should render a live metrics response" do
      rack_request.update_param("live_time", (Time.now - 120).iso8601)
      request = SpartanAPM::Web::ApiRequest.new(rack_request)
      response = request.live_metrics
      expect(response.keys).to eq [:env, :app, :host, :action, :hosts, :actions, :minutes, :interval_minutes, :times, :avg, :p50, :p90, :p99, :throughput, :errors, :error_rate]
    end

    it "should render an empty response if there are no new metrics" do
      rack_request.update_param("live_time", (Time.now - 59).iso8601)
      request = SpartanAPM::Web::ApiRequest.new(rack_request)
      response = request.live_metrics
      expect(response).to eq({})
    end
  end

  describe "actions" do
    it "should render a list of actions" do
      request = SpartanAPM::Web::ApiRequest.new(rack_request)
      response = request.actions
      expect(response).to match({
        actions: [
          {name: "action_1", load: instance_of(Float)},
          {name: "action_2", load: instance_of(Float)},
          {name: "action_3", load: instance_of(Float)},
          {name: "action_4", load: instance_of(Float)}
        ]
      })
    end
  end

  describe "hosts" do
    it "should render an hosts response" do
      request = SpartanAPM::Web::ApiRequest.new(rack_request)
      response = request.hosts
      expect(response).to match({
        "host_1" => {requests: 19, errors: 2, time: 2130},
        "host_2" => {requests: 11, errors: 0, time: 1080}
      })
    end
  end

  describe "errors" do
    it "should render an errors response" do
      request = SpartanAPM::Web::ApiRequest.new(rack_request)
      response = request.errors
      expect(response).to match({
        errors: [
          {
            class_name: "ArgumentError",
            message: "ArgumentError",
            count: 1,
            backtrace: instance_of(Array)
          },
          {
            class_name: "StandardError",
            message: "StandardError",
            count: 1,
            backtrace: instance_of(Array)
          }
        ]
      })
    end
  end
end
