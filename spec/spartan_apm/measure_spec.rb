# frozen_string_literal: true

require_relative "../spec_helper"

describe SpartanAPM::Measure do
  describe "current_measures" do
    it "should keep track of the current measures", freeze_time: true do
      expect(SpartanAPM::Persistence).to_not receive(:store!)
      measure = SpartanAPM::Measure.new("app", "test")
      SpartanAPM::Measure.current_measures << measure
      expect(SpartanAPM::Measure.current_measures).to eq [measure]
    end

    it "should persist all queued up measures if it has not been persisted in over one minute" do
      save_val = SpartanAPM.persist_asynchronously?
      begin
        SpartanAPM.persist_asynchronously = false
        time = Time.now
        Timecop.freeze(time) do
          measure_1 = SpartanAPM::Measure.new("app", "test_2")
          measure_2 = SpartanAPM::Measure.new("app", "test_2")
          measure_3 = SpartanAPM::Measure.new("app", "test_3")
          measure_1.capture_time("stat", 1)
          measure_1.record!
          measure_2.capture_time("stat", 2)
          measure_2.record!
          expect(SpartanAPM::Measure.current_measures).to eq [measure_1, measure_2]
          expect(SpartanAPM::Persistence).to receive(:store!).with(SpartanAPM.bucket(time), [measure_1, measure_2]).and_call_original
          Timecop.travel(time + 60) do
            measure_3.capture_time("stat", 3)
            measure_3.record!
            expect(SpartanAPM::Measure.current_measures).to eq [measure_3]
          end
        ensure
          SpartanAPM::Persistence.new("app").clear!(time)
          SpartanAPM::Persistence.new("app").clear!(time + 60)
        end
      ensure
        SpartanAPM.persist_asynchronously = save_val
      end
    end
  end

  describe "sample rate" do
    it "should only record a fraction of the requests if the sample rate is set"

    it "should always record errors even if the sample rate is set"
  end
end
