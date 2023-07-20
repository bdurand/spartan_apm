# frozen_string_literal: true

require_relative "../../../spec_helper"

describe SpartanAPM::Middleware::Sidekiq::StartMiddleware, freeze_time: true do
  let(:middleware) { SpartanAPM::Middleware::Sidekiq::StartMiddleware.new }

  it "should persist the start time to the environment" do
    msg = {}
    result = middleware.call(Object.new, msg, "queue") { :foobar }
    expect(result).to eq :foobar
    expect(msg["spartan_apm.middleware_start_time"]).to eq SpartanAPM.clock_time
  end

  it "should capture the queue time" do
    msg = {"enqueued_at" => (Time.now - 0.5).to_f}
    middleware.call(Object.new, msg, "queue") { :foobar }
    measures = SpartanAPM::Measure.current_measures
    expect(measures.size).to eq 1
    expect(measures.first.app).to eq "sidekiq"
    expect(measures.first.action).to eq "Object"
    expect(measures.first.timers.keys).to eq [:queue]
    expect(measures.first.timers.values.collect { |time| time.round(2) }).to eq [0.5]
  end

  it "should ignore jobs by class name" do
    SpartanAPM.ignore_requests("sidekiq", "Obj*")
    begin
      expect(SpartanAPM).not_to receive(:measure)
      middleware.call(Object.new, {}, "queue") { :foobar }
    ensure
      SpartanAPM.ignore_requests("sidekiq", nil)
    end
  end
end
