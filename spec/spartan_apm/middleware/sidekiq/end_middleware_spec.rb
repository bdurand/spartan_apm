# frozen_string_literal: true

require_relative "../../../spec_helper"

describe SpartanAPM::Middleware::Sidekiq::EndMiddleware, freeze_time: true do
  let(:middleware) { SpartanAPM::Middleware::Sidekiq::EndMiddleware.new }

  it "should capture the middleware time" do
    msg = {"spartan_apm.middleware_start_time" => (Time.now - 0.5).to_f}
    SpartanAPM.measure("sidekiq", "test") do
      result = middleware.call(Object.new, msg, "queue") { :foobar }
      expect(result).to eq :foobar
    end
    measure = SpartanAPM::Measure.current_measures.first
    expect(measure.timers[:middleware].round(1)).to eq 0.5
  end

  it "should capture the app time" do
    msg = {}
    SpartanAPM.measure("sidekiq", "test") do
      result = middleware.call(Object.new, msg, "queue") { :foobar }
    end
    measure = SpartanAPM::Measure.current_measures.first
    expect(measure.timers).to include :app
  end
end
