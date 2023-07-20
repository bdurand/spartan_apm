# frozen_string_literal: true

require_relative "../../../spec_helper"

describe SpartanAPM::Middleware::Rack::EndMiddleware, freeze_time: true do
  let(:response) { [204, {}, []] }
  let(:app) { lambda { |env| response } }
  let(:middleware) { SpartanAPM::Middleware::Rack::EndMiddleware.new(app) }

  it "should wrap a Rack app" do
    expect(middleware.call({})).to eq response
  end

  it "should capture middleware time" do
    SpartanAPM.measure("web", "test") do
      middleware.call("spartan_apm.middleware_start_time" => (SpartanAPM.clock_time - 0.5).to_f)
    end
    measure = SpartanAPM::Measure.current_measures.first
    expect(measure.timers[:middleware].round(3)).to eq 0.5
  end

  it "should capture the app time" do
    SpartanAPM.measure("web", "test") do
      middleware.call({})
    end
    measure = SpartanAPM::Measure.current_measures.first
    expect(measure.timers).to include :app
  end
end
