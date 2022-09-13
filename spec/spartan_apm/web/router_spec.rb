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

  it "should be render the index page" do
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

  it "should be render metrics API response" do
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

  it "should be render actions API response" do
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

  it "should be render errors API response" do
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

  it "should be usable as middleware" do
    SpartanAPM::Persistence.store!(SpartanAPM.bucket(time), [measure])
    begin
      parent_app = lambda { |env| [204, {}, []] }
      app = SpartanAPM::Web::Router.new(parent_app, "/apm")
      response = app.call({"HTTP_HOST" => "apm.example.com", "PATH_INFO" => "/resource", "rack.input" => ""})
      expect(response).to eq [204, {}, []]
      status, headers, body = app.call({"HTTP_HOST" => "apm.example.com", "PATH_INFO" => "/apm", "HTTPS" => "on", "QUERY_STRING" => "app=web", "rack.input" => ""})
      expect(status).to eq 302
      expect(headers).to eq({"location" => "https://apm.example.com/apm/?app=web"})
      status, headers, body = app.call({"HTTP_HOST" => "apm.example.com", "PATH_INFO" => "/apm/", "rack.input" => ""})
      expect(status).to eq 200
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
