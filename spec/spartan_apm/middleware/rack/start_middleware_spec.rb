# frozen_string_literal: true

require_relative "../../../spec_helper"

describe SpartanAPM::Middleware::Rack::StartMiddleware, freeze_time: true do
  let(:response) { [204, {}, []] }
  let(:app) {
    lambda { |env|
      SpartanAPM.current_action = "test"
      response
    }
  }
  let(:middleware) { SpartanAPM::Middleware::Rack::StartMiddleware.new(app) }

  it "should wrap a Rack app" do
    expect(middleware.call({})).to eq response
  end

  it "should persist the start time to the environment" do
    env = {}
    middleware.call(env)
    expect(env["spartan_apm.middleware_start_time"]).to eq Time.now.to_f
  end

  it "should capture the queue time if the HTTP_X_REQUEST_START header is specified in seconds" do
    middleware.call("HTTP_X_REQUEST_START" => (Time.now.to_f - 0.5).to_s)
    measures = SpartanAPM::Measure.current_measures
    expect(measures.size).to eq 1
    expect(measures.first.app).to eq "web"
    expect(measures.first.action).to eq "test"
    expect(measures.first.timers.keys).to eq [:queue]
    expect(measures.first.timers.values.collect { |time| time.round(2) }).to eq [0.5]
  end

  it "should capture the queue time if the HTTP_X_QUEUE_START header is specified in seconds" do
    middleware.call("HTTP_X_QUEUE_START" => (Time.now.to_f - 0.5).to_s)
    measures = SpartanAPM::Measure.current_measures
    expect(measures.size).to eq 1
    expect(measures.first.app).to eq "web"
    expect(measures.first.action).to eq "test"
    expect(measures.first.timers.keys).to eq [:queue]
    expect(measures.first.timers.values.collect { |time| time.round(2) }).to eq [0.5]
  end

  it "should capture the queue time if the header is prefixed with t=" do
    middleware.call("HTTP_X_REQUEST_START" => "t=#{Time.now.to_f - 0.5}")
    measures = SpartanAPM::Measure.current_measures
    expect(measures.first.timers[:queue].round(2)).to eq(0.5)
  end

  it "should capture the queue time if the header is specified in milliseconds" do
    middleware.call("HTTP_X_REQUEST_START" => ((Time.now.to_f - 0.5) * 1000).round.to_s)
    measures = SpartanAPM::Measure.current_measures
    expect(measures.first.timers[:queue].round(2)).to eq(0.5)
  end

  it "should capture the queue time if the header is specified in microseconds" do
    middleware.call("HTTP_X_REQUEST_START" => ((Time.now.to_f - 0.5) * 1_000_000).round.to_s)
    measures = SpartanAPM::Measure.current_measures
    expect(measures.first.timers[:queue].round(2)).to eq(0.5)
  end

  it "should ignore requests by path" do
    SpartanAPM.ignore_requests("web", "/info/*")
    begin
      expect(SpartanAPM).not_to receive(:measure)
      middleware.call("PATH_INFO" => "/info/debug")
    ensure
      SpartanAPM.ignore_requests("web", nil)
    end
  end
end
