# frozen_string_literal: true

require_relative "spec_helper"

describe SpartanAPM do
  describe "redis" do
    it "should use a specific redis instance" do
      save_val = SpartanAPM.redis
      begin
        SpartanAPM.redis = :redis
        expect(SpartanAPM.redis).to eq :redis
      ensure
        SpartanAPM.redis = save_val
      end
    end

    it "should call a block to get a runtime redis instance" do
      save_val = SpartanAPM.redis
      begin
        SpartanAPM.redis = lambda { :redis }
        expect(SpartanAPM.redis).to eq :redis
      ensure
        SpartanAPM.redis = save_val
      end
    end
  end

  describe "sample_rate" do
    it "should sample a 100% by default" do
      expect(SpartanAPM.sample_rate).to eq 1.0
    end

    it "should set a sample rate" do
      save_val = SpartanAPM.sample_rate
      begin
        SpartanAPM.sample_rate = 0.5
        expect(SpartanAPM.sample_rate).to eq 0.5
      ensure
        SpartanAPM.sample_rate = save_val
      end
    end
  end

  describe "measure" do
    it "should measure statistics in a block" do
      expect_any_instance_of(SpartanAPM::Measure).to receive(:record!)
      retval = SpartanAPM.measure("app", "test") { :retval }
      expect(retval).to eq :retval
    end

    it "should not measure in a block if the request is not sampled" do
      begin
        SpartanAPM.sample_rate = 0.0
        expect_any_instance_of(SpartanAPM::Measure).to_not receive(:record!)
        retval = SpartanAPM.measure("app", "test") { :retval }
        expect(retval).to eq :retval
      ensure
        SpartanAPM.sample_rate = 1.0
      end
    end

    it "should capture any errors", freeze_time: true do
      measure = nil
      error = ArgumentError.new("boom")
      expect {
        SpartanAPM.measure("app", "test") {
          measure = Thread.current[:spartan_apm_measure]
          raise error
        }
      }.to raise_error(error)
      expect(measure.error).to eq error.class.name
      expect(measure.error_message).to eq error.message
      expect(measure.error_backtrace).to eq error.backtrace
    end
  end

  describe "capture" do
    it "should do nothing if the request is not being measured" do
      retval = SpartanAPM.capture(:app) { :retval }
      expect(retval).to eq :retval
    end

    it "should capture the timing if the request is being measured", freeze_time: true do
      begin
        SpartanAPM.measure("app", "test") do
          measure = Thread.current[:spartan_apm_measure]
          retval = SpartanAPM.capture(:app) { :retval }
          expect(retval).to eq :retval
          expect(measure.timers).to match({app: Float})
          expect(measure.counts).to match({app: 1})
        end
      ensure
        SpartanAPM::Persistence.new("app").clear!(Time.now)
      end
    end

    it "should increment the timing if it's already been set", freeze_time: true do
      time = Time.now
      begin
        SpartanAPM.measure("app", "test") do
          measure = Thread.current[:spartan_apm_measure]
          SpartanAPM.capture(:app) { Timecop.travel(time + 1) }
          Timecop.travel(time + 2)
          SpartanAPM.capture(:app) { Timecop.travel(time + 3) }
          expect(measure.timers[:app].round).to eq 2.0
          expect(measure.counts[:app]).to eq 2
        end
      ensure
        SpartanAPM::Persistence.new("app").clear!([time, time + 3])
      end
    end

    it "should capture individual components in nested blocks without duplication" do
      time = Time.now
      begin
        SpartanAPM.measure("app", "test") do
          measure = Thread.current[:spartan_apm_measure]
          SpartanAPM.capture(:app) do
            Timecop.travel(time + 0.25)
            SpartanAPM.capture(:database) do
              Timecop.travel(time + 0.25 + 0.125)
            end
            Timecop.travel(time + 0.25 + 0.125 + 0.5)
            SpartanAPM.capture(:database) do
              Timecop.travel(time + 0.25 + 0.125 + 0.5 + 0.075)
            end
            Timecop.travel(time + 0.25 + 0.125 + 0.5 + 0.1)
          end
          expect(measure.timers[:app].round(1)).to eq 0.8
          expect(measure.timers[:database].round(2)).to eq 0.2
        end
      ensure
        SpartanAPM::Persistence.new("app").clear!([time, time + 1])
      end
    end

    it "should not capture additional block metrics inside an exclusive block" do
      begin
        SpartanAPM.measure("app", "test") do
          measure = Thread.current[:spartan_apm_measure]
          SpartanAPM.capture(:elasticsearch, exclusive: true) do
            SpartanAPM.capture(:http) do
              Timecop.travel(Time.now + 0.5)
            end
          end
          expect(measure.timers[:elasticsearch].round(1)).to eq 0.5
          expect(measure.timers).to_not include(:http)
        end
      ensure
        SpartanAPM::Persistence.new("app").clear!(Time.now)
      end
    end

    it "should be able to override the current action and app from inside a block" do
      SpartanAPM.measure("app", "test") do
        SpartanAPM.current_app = "foo"
        SpartanAPM.current_action = "bar"
        measure = Thread.current[:spartan_apm_measure]
        expect(measure.app).to eq "foo"
        expect(measure.action).to eq "bar"
      end
    end

    it "should do nothing if the current action and app are set outside a block" do
      SpartanAPM.current_app = "foo"
      SpartanAPM.current_action = "bar"
      SpartanAPM.measure("app", "test") do
        measure = Thread.current[:spartan_apm_measure]
        expect(measure.app).to eq "app"
        expect(measure.action).to eq "test"
      end
    end
  end

  describe "capture_time" do
    it "should allow incrementing a value without a block", freeze_time: true do
      begin
        SpartanAPM.measure("app", "test") do
          measure = Thread.current[:spartan_apm_measure]
          SpartanAPM.capture_time(:app, 1)
          SpartanAPM.capture_time(:app, 2.5)
          expect(measure.timers[:app]).to eq 3.5
          expect(measure.counts[:app]).to eq 2
        end
      ensure
        SpartanAPM::Persistence.new("app").clear!(Time.now)
      end
    end
  end

  describe "capture_error" do
    it "should capture an error in the current measure" do
      SpartanAPM.measure("app", "test") do
        error = ArgumentError.new
        SpartanAPM.capture_error(error)
        measure = Thread.current[:spartan_apm_measure]
        expect(measure.error).to eq error.class.name
      end
    end

    it "should do nothing if there is no current measure" do
      error = ArgumentError.new
      expect { SpartanAPM.capture_error(error) }.to_not raise_error
    end

    it "should do nothing the error should be ignored" do
      begin
        SpartanAPM.ignore_errors([ArgumentError])
        SpartanAPM.measure("app", "test") do
          error = ArgumentError.new
          SpartanAPM.capture_error(error)
          measure = Thread.current[:spartan_apm_measure]
          expect(measure.error).to eq nil
        end
      ensure
        SpartanAPM.ignore_errors(nil)
      end
    end
  end

  describe "ttl" do
    it "should have a ttl that is used for expiring Redis keys" do
      save_val = SpartanAPM.ttl
      begin
        value = rand(10000000)
        SpartanAPM.ttl = value
        expect(SpartanAPM.ttl).to eq value
      ensure
        SpartanAPM.ttl = save_val
      end
    end
  end

  describe "host" do
    it "should be the local socket hostname" do
      expect(SpartanAPM.host).to eq Socket.gethostname
    end
  end

  describe "bucket" do
    it "should get the bucket for segmenting stats to the nearest minute" do
      time = Time.now
      bucket = SpartanAPM.bucket(time)
      time_from_bucket = Time.at(bucket * 60)
      difference = time - time_from_bucket
      expect(difference).to be >= 0
      expect(difference).to be < 60
    end
  end

  describe "ignore_error?" do
    it "should return false if there is no list of error to ignore" do
      SpartanAPM.ignore_errors(nil)
      expect(SpartanAPM.ignore_error?(ArgumentError.new)).to eq false
    end

    it "should ignore errors by class" do
      begin
        SpartanAPM.ignore_errors([ArgumentError])
        expect(SpartanAPM.ignore_error?(ArgumentError.new)).to eq true
        expect(SpartanAPM.ignore_error?(StandardError.new)).to eq false
      ensure
        SpartanAPM.ignore_errors(nil)
      end
    end

    it "should ignore errors by class name" do
      begin
        SpartanAPM.ignore_errors(["ArgumentError"])
        expect(SpartanAPM.ignore_error?(ArgumentError.new)).to eq true
        expect(SpartanAPM.ignore_error?(StandardError.new)).to eq false
      ensure
        SpartanAPM.ignore_errors(nil)
      end
    end
  end

  describe "clean_backtrace" do
    it "should run a backtrace cleaner" do
      begin
        SpartanAPM.backtrace_cleaner = lambda { |trace| trace.reject { |line| line.include?("c") } }
        backtrace = ["a", "b", "c"]
        expect(SpartanAPM.clean_backtrace(backtrace)).to eq ["a", "b"]
      ensure
        SpartanAPM.backtrace_cleaner = nil
      end
    end

    it "should do nothing if there is no backtrace cleaner" do
      begin
        SpartanAPM.backtrace_cleaner = nil
        backtrace = ["a", "b", "c"]
        expect(SpartanAPM.clean_backtrace(backtrace)).to eq ["a", "b", "c"]
      ensure
        SpartanAPM.backtrace_cleaner = nil
      end
    end

    it "should always leave the first line" do
      begin
        SpartanAPM.backtrace_cleaner = lambda { |trace| trace.reject { |line| line.include?("a") } }
        backtrace = ["a1", "a2", "c"]
        expect(SpartanAPM.clean_backtrace(backtrace)).to eq ["a1", "c"]
      ensure
        SpartanAPM.backtrace_cleaner = nil
      end
    end
  end

  describe "ignore_request?" do
    it "should ignore app requests by value" do
      SpartanAPM.ignore_requests("web", "/health-check", "/debug/*", /f[ou]o/i)
      begin
        expect(SpartanAPM.ignore_request?("web", "/")).to eq false
        expect(SpartanAPM.ignore_request?("web", "/health-check")).to eq true
        expect(SpartanAPM.ignore_request?("web", "/health-check/db")).to eq false
        expect(SpartanAPM.ignore_request?("web", "/debugger")).to eq false
        expect(SpartanAPM.ignore_request?("web", "/debug/stuff")).to eq true
        expect(SpartanAPM.ignore_request?("web", "/Foobar")).to eq true
      ensure
        SpartanAPM.ignore_requests("web", nil)
      end
    end
  end
end
