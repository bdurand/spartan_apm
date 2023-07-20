# frozen_string_literal: true

require_relative "../../spec_helper"

describe SpartanAPM::Web::Router, freeze_time: true do
  let(:time) { Time.now - 120 }
  let(:measure) {
    measure = SpartanAPM::Measure.new("web", "test")
    measure.timers[:app] = 0.5
    measure.timers[:database] = 0.25
    measure
  }

  it "should render the index page" do
    SpartanAPM::Persistence.store!(SpartanAPM.bucket(time), [measure])
    begin
      app = SpartanAPM::Web::Router.new
      status, headers, body = app.call({"PATH_INFO" => "/", "rack.input" => ""})
      expect(status).to eq 200
      expect(headers["content-type"]).to eq "text/html; charset=utf-8"
      expect(body.join).to include "<title>SpartanAPM</title>"
    ensure
      SpartanAPM::Persistence.new("web").clear!(time)
    end
  end

  it "should render assets" do
    app = SpartanAPM::Web::Router.new
    status, headers, body = app.call({"PATH_INFO" => "/assets/spartan.svg", "rack.input" => ""})
    expect(status).to eq 200
    expect(headers["content-type"]).to eq "image/svg+xml; charset=utf-8"
    expect(body.join).to eq File.read(File.expand_path(File.join(__dir__, "..", "..", "..", "app", "assets", "spartan.svg")))
  end

  it "should render the metrics API response" do
    SpartanAPM::Persistence.store!(SpartanAPM.bucket(time), [measure])
    begin
      app = SpartanAPM::Web::Router.new
      status, headers, body = app.call({"PATH_INFO" => "/metrics", "rack.input" => ""})
      expect(status).to eq 200
      expect(headers["content-type"]).to eq "application/json; charset=utf-8"
    ensure
      SpartanAPM::Persistence.new("web").clear!(time)
    end
  end

  it "should render the live metrics API response" do
    SpartanAPM::Persistence.store!(SpartanAPM.bucket(time), [measure])
    begin
      app = SpartanAPM::Web::Router.new
      status, headers, body = app.call({"PATH_INFO" => "/live_metrics", "rack.input" => ""})
      expect(status).to eq 200
      expect(headers["content-type"]).to eq "application/json; charset=utf-8"
    ensure
      SpartanAPM::Persistence.new("web").clear!(time)
    end
  end

  it "should render the actions API response" do
    SpartanAPM::Persistence.store!(SpartanAPM.bucket(time), [measure])
    begin
      app = SpartanAPM::Web::Router.new
      status, headers, body = app.call({"PATH_INFO" => "/actions", "rack.input" => ""})
      expect(status).to eq 200
      expect(headers["content-type"]).to eq "application/json; charset=utf-8"
    ensure
      SpartanAPM::Persistence.new("web").clear!(time)
    end
  end

  it "should render the errors API response" do
    SpartanAPM::Persistence.store!(SpartanAPM.bucket(time), [measure])
    begin
      app = SpartanAPM::Web::Router.new
      status, headers, body = app.call({"PATH_INFO" => "/errors", "rack.input" => ""})
      expect(status).to eq 200
      expect(headers["content-type"]).to eq "application/json; charset=utf-8"
    ensure
      SpartanAPM::Persistence.new("web").clear!(time)
    end
  end

  it "should render the hosts API response" do
    SpartanAPM::Persistence.store!(SpartanAPM.bucket(time), [measure])
    begin
      app = SpartanAPM::Web::Router.new
      status, headers, body = app.call({"PATH_INFO" => "/hosts", "rack.input" => ""})
      expect(status).to eq 200
      expect(headers["content-type"]).to eq "application/json; charset=utf-8"
    ensure
      SpartanAPM::Persistence.new("web").clear!(time)
    end
  end

  it "should return a not found response if the path doesn't match" do
    app = SpartanAPM::Web::Router.new
    status, headers, body = app.call({"PATH_INFO" => "/resource", "rack.input" => ""})
    expect(status).to eq 404
  end
end
