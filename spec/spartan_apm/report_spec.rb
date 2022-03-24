# frozen_string_literal: true

require_relative "../spec_helper"

describe SpartanAPM::Report, freeze_time: true do
  let(:end_time) { SpartanAPM.bucket_time(SpartanAPM.bucket(Time.now - 60)) }
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
        measure.timers["database"] = value.to_f / 1000.0
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

  describe "each_time" do
    it "should iterate over all time frames" do
      report = SpartanAPM::Report.new(app, start_time + 10, start_time + 126)
      times = []
      report.each_time do |time|
        times << time
      end
      expect(times).to eq [start_time, start_time + 60, start_time + 120]
      expect(report.minutes).to eq 3
    end
  end

  describe "component_request_time" do
    it "should calculate average request time for a component" do
      report = SpartanAPM::Report.new(app, start_time, end_time)
      expect(report.component_request_time(start_time, "app")).to eq 70
      expect(report.component_request_time(end_time, "app")).to eq 76
      expect(report.component_request_time(start_time, "database")).to eq 35
    end
  end

  describe "request_time" do
    it "should calculate average request time for a metric" do
      report = SpartanAPM::Report.new(app, start_time, end_time)
      expect(report.request_time(start_time, :avg)).to eq 104
      expect(report.request_time(end_time, :p50)).to eq 120
      expect(report.request_time(end_time, :p90)).to eq 180
      expect(report.request_time(end_time, :p99)).to eq 210
    end
  end

  describe "avg_component_time" do
    it "should calculate the average total request time for a metric" do
      report = SpartanAPM::Report.new(app, start_time, end_time)
      expect(report.avg_component_time("app")).to eq 74
      expect(report.avg_component_time("database")).to eq 37
    end
  end

  describe "avg_request_time" do
    it "should calculate the average total request time for a metric" do
      report = SpartanAPM::Report.new(app, start_time, end_time)
      expect(report.avg_request_time(:avg)).to eq 111
      expect(report.avg_request_time(:p99)).to eq 195
    end
  end

  describe "request_count" do
    it "should the number of requests for a time" do
      report = SpartanAPM::Report.new(app, start_time, end_time)
      expect(report.request_count(start_time)).to eq 22
      expect(report.request_count(end_time)).to eq 12
    end
  end

  describe "requests_per_minute" do
    it "should calculate requests per minute for a time" do
      report = SpartanAPM::Report.new(app, start_time, end_time)
      expect(report.requests_per_minute(start_time)).to eq 22
      expect(report.requests_per_minute(end_time)).to eq 12
    end

    it "should calculate requests per minute for a time when intervals are rolled up" do
      report = SpartanAPM::Report.new(app, start_time, end_time)
      allow(report).to receive(:interval_minutes).and_return(3)
      expect(report.requests_per_minute(start_time)).to eq 14
    end
  end

  describe "avg_requests_per_minute" do
    it "should calculate the average request per minute" do
      report = SpartanAPM::Report.new(app, start_time, end_time)
      expect(report.avg_requests_per_minute).to eq 14
    end
  end

  describe "errors" do
    it "should get a list of all errors with their counts" do
      report = SpartanAPM::Report.new(app, start_time, end_time)
      data = report.errors.collect { |e| [e.class_name, e.count] }
      expect(data).to eq [["ArgumentError", 3], ["StandardError", 2]]
    end
  end

  describe "error_count" do
    it "should get the count of errors at a time" do
      report = SpartanAPM::Report.new(app, start_time, end_time)
      expect(report.error_count(start_time)).to eq 2
      expect(report.error_count(start_time + 60)).to eq 0
      expect(report.error_count(start_time + 120)).to eq 3
    end
  end

  describe "avg_errors_per_minute" do
    it "should get average error count" do
      report = SpartanAPM::Report.new(app, start_time, end_time)
      expect(report.avg_errors_per_minute).to eq 1.67
    end
  end

  describe "error_rate" do
    it "should get the error rate at a time" do
      report = SpartanAPM::Report.new(app, start_time, end_time)
      expect(report.error_rate(start_time).round(3)).to eq 0.091
      expect(report.error_rate(start_time + 60).round(3)).to eq 0.0
      expect(report.error_rate(start_time + 120).round(3)).to eq 0.25
    end
  end

  describe "avg_error_rate" do
    it "should get average error count" do
      report = SpartanAPM::Report.new(app, start_time, end_time)
      expect(report.avg_error_rate.round(3)).to eq 0.114
    end
  end

  describe "actions" do
    it "should load a list of top actions" do
      report = SpartanAPM::Report.new(app, start_time, end_time)
      expect(report.actions).to eq ["action_1", "action_2", "action_3", "action_4"]
    end
  end

  describe "action_load" do
    it "should get the load percentage used by a specific action" do
      report = SpartanAPM::Report.new(app, start_time, end_time)
      expect(report.action_percent_time("action_1").round(2)).to eq 0.48
      expect(report.action_percent_time("action_2").round(2)).to eq 0.31
    end
  end

  describe "hosts" do
    it "should get the list of hosts used" do
      expect(SpartanAPM::Report.new(app, start_time, end_time).hosts).to eq ["host_1", "host_2"]
      expect(SpartanAPM::Report.new(app, end_time, end_time).hosts).to eq ["host_1"]
    end
  end

  describe "name" do
    it "should get the list of the names used" do
      expect(SpartanAPM::Report.new(app, start_time, end_time).component_names).to match_array ["app", "database"]
    end
  end
end
