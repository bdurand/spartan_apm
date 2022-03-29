# frozen_string_literal: true

require_relative "../spec_helper"

describe SpartanAPM::Persistence do
  def sample_stats(app, action, additional_stats)
    stats = []
    (1..100).each do |value|
      measure = SpartanAPM::Measure.new(app, action)
      stats << measure
      additional_stats.keys.each do |name|
        measure.timers[name] = value.to_f / 1000.0
        measure.counts[name] = (value / 10) + 1
      end
    end
    measure = SpartanAPM::Measure.new(app, action)
    stats << measure
    additional_stats.each do |name, value|
      measure.timers[name] = value.to_f / 1000.0
      measure.counts[name] = (value / 10) + 1
    end
    stats.shuffle
  end

  describe "store!" do
    it "should store aggregated statistics for both specific contexts and the root level contexts" do
      time = Time.now
      sample = (1..100).to_a.shuffle
      bucket_1 = SpartanAPM.bucket(time - 120)
      bucket_2 = SpartanAPM.bucket(time - 60)
      bucket_3 = SpartanAPM.bucket(time)
      bucket_1_web_1_measures = sample_stats("web", "context_1", "stat_1" => 500, "stat_2" => 200)
      bucket_1_web_1_measures.last.capture_error(ArgumentError.new)
      bucket_1_async_1_measures = sample_stats("async", "context_1", "stat_1" => 300, "stat_2" => 400)
      bucket_2_web_1_measures = sample_stats("web", "context_1", "stat_1" => 120, "stat_2" => 220)
      bucket_2_async_1_measures = sample_stats("async", "context_1", "stat_1" => 320, "stat_2" => 420)
      bucket_3_web_1_measures = sample_stats("web", "context_1", "stat_1" => 140, "stat_2" => 240)
      bucket_3_async_1_measures = sample_stats("async", "context_1", "stat_1" => 340, "stat_2" => 440)
      bucket_1_web_2_measures = sample_stats("web", "context_2", "stat_1" => 160, "stat_2" => 260)
      bucket_2_async_2_measures = sample_stats("async", "context_2", "stat_1" => 360, "stat_2" => 460)
      bucket_1_web_1_other_host_measures = sample_stats("web", "context_1", "stat_1" => 170, "stat_2" => 270)
      bucket_1_web_1_other_host_measures.last.capture_error(ArgumentError.new)

      web = SpartanAPM::Persistence.new("web")
      async = SpartanAPM::Persistence.new("async")

      begin
        allow(SpartanAPM).to receive(:host).and_return("testhost_1")
        SpartanAPM::Persistence.store!(bucket_1, bucket_1_web_1_measures + bucket_1_async_1_measures + bucket_1_web_2_measures)
        SpartanAPM::Persistence.store!(bucket_2, bucket_2_web_1_measures + bucket_2_async_1_measures + bucket_2_async_2_measures)
        SpartanAPM::Persistence.store!(bucket_3, bucket_3_web_1_measures + bucket_3_async_1_measures)
        allow(SpartanAPM).to receive(:host).and_return("testhost_2")
        SpartanAPM::Persistence.store!(bucket_1, bucket_1_web_1_other_host_measures)
        SpartanAPM::Persistence.store!(bucket_1, bucket_1_web_1_measures)

        web_1_metrics = web.metrics([time - 120, time], action: "context_1")
        web_2_metrics = web.metrics([time - 120, time], action: "context_2")
        async_1_metrics = async.metrics([time - 120, time], action: "context_1")
        async_2_metrics = async.metrics([time - 120, time], action: "context_2")
        async_all_metrics = async.metrics([time - 120, time])
        web_all_metrics = web.metrics([time - 120, time])
        web_1_partial_metrics = web.metrics([time - 60, time], action: "context_1")
        web_1_testhost_2_metrics = web.metrics([time - 120, time], action: "context_1", host: "testhost_2")

        expect(web_1_metrics.collect(&:time)).to eq [Time.at(bucket_1 * 60), Time.at(bucket_2 * 60), Time.at(bucket_3 * 60)]
        expect(web_1_metrics.collect(&:count)).to eq [303, 101, 101]
        expect(web_1_metrics.collect(&:avg)).to eq [106, 103, 104]
        expect(web_1_metrics.collect(&:p50)).to eq [102, 102, 102]
        expect(web_1_metrics.collect(&:p90)).to eq [182, 182, 182]
        expect(web_1_metrics.collect(&:p99)).to eq [200, 200, 200]
        expect(web_1_metrics.collect(&:error_count)).to eq [3, 0, 0]
        expect(web_1_metrics.collect { |m| m.component_request_time(:stat_1) }).to eq [54, 51, 51]
        expect(web_1_metrics.collect { |m| m.component_request_time(:stat_2) }).to eq [52, 52, 52]

        expect(web_2_metrics.collect(&:time)).to eq [Time.at(bucket_1 * 60)]
        expect(web_2_metrics.collect(&:count)).to eq [101]

        expect(async_1_metrics.collect(&:time)).to eq [Time.at(bucket_1 * 60), Time.at(bucket_2 * 60), Time.at(bucket_3 * 60)]
        expect(async_1_metrics.collect(&:count)).to eq [101, 101, 101]

        expect(async_2_metrics.collect(&:time)).to eq [Time.at(bucket_2 * 60)]
        expect(async_2_metrics.collect(&:count)).to eq [101]

        expect(async_all_metrics.collect(&:time)).to eq [Time.at(bucket_1 * 60), Time.at(bucket_2 * 60), Time.at(bucket_3 * 60)]
        expect(async_all_metrics.collect(&:count)).to eq [101, 202, 101]
        expect(async_all_metrics.collect(&:avg)).to eq [107, 108, 108]
        expect(async_all_metrics.collect(&:p50)).to eq [102, 102, 102]
        expect(async_all_metrics.collect(&:p90)).to eq [182, 182, 182]
        expect(async_all_metrics.collect(&:p99)).to eq [200, 200, 200]

        expect(web_all_metrics.collect(&:time)).to eq [Time.at(bucket_1 * 60), Time.at(bucket_2 * 60), Time.at(bucket_3 * 60)]
        expect(web_all_metrics.collect(&:count)).to eq [404, 101, 101]
        expect(web_all_metrics.collect(&:avg)).to eq [119, 103, 104]
        expect(web_all_metrics.collect(&:p50)).to eq [102, 102, 102]
        expect(web_all_metrics.collect(&:p90)).to eq [182, 182, 182]
        expect(web_all_metrics.collect(&:p99)).to eq [200, 200, 200]

        expect(web_1_partial_metrics.collect(&:time)).to eq [Time.at(bucket_2 * 60), Time.at(bucket_3 * 60)]
        expect(web_1_partial_metrics.collect(&:count)).to eq [101, 101]

        expect(web_1_testhost_2_metrics.collect(&:time)).to eq [Time.at(bucket_1 * 60)]
        expect(web_1_testhost_2_metrics.collect(&:count)).to eq [202]
      ensure
        web.clear!([time - 120, time])
        async.clear!([time - 120, time])
      end
    end

    it "should estimate the counts if the measures are being sampled"

    it "should store stats for the last hour", freeze_time: true do
      app = SpartanAPM::Persistence.new("app")
      base_time = Time.utc(2022, 2, 22, 12, 0)
      app.delete_hourly_stats!
      begin
        61.times do |minute|
          measure = SpartanAPM::Measure.new("app", "action")
          measure.capture_time("app", 0.01 * (minute + 1))
          measure.capture_time("database", 0.02 * (minute + 1))
          measure.capture_error(ArgumentError.new) if minute % 4 == 0
          bucket = SpartanAPM.bucket(base_time + (minute * 60))
          SpartanAPM::Persistence.store!(bucket, [measure])
        end
        metrics = app.hourly_metrics(base_time)
        expect(metrics.size).to eq 1
        metric = metrics.first
        expect(metric.time).to eq base_time
        expect(metric.count).to eq 60
        expect(metric.error_count).to eq 15
        expect(metric.components).to eq({"app" => [305, 1.0], "database" => [610, 1.0]})
        expect(metric.avg).to eq 915
        expect(metric.p50).to eq 915
        expect(metric.p90).to eq 915
        expect(metric.p99).to eq 915
      ensure
        app.clear!([base_time, base_time + (61 * 60)])
      end
    end

    it "should truncate actions when storing hourly stats", freeze_time: true do
      app = SpartanAPM::Persistence.new("app")
      base_time = Time.utc(2022, 2, 22, 12, 0)
      app.delete_hourly_stats!
      save_val = SpartanAPM.max_actions
      begin
        SpartanAPM.max_actions = 2
        3.times do |i|
          measure = SpartanAPM::Measure.new("app", "action#{i}")
          measure.capture_time("app", 0.01 * (i + 1))
          measure.capture_time("database", 0.02 * (i + 1))
          bucket = SpartanAPM.bucket(base_time)
          SpartanAPM::Persistence.store!(bucket, [measure])
        end
        SpartanAPM::Persistence.store!(SpartanAPM.bucket(base_time + (60 * 60)), [SpartanAPM::Measure.new("app", "action0")])
        expect(app.metrics([base_time, base_time + (60 * 60)], action: "action0").size).to eq 0
        expect(app.metrics([base_time, base_time + (60 * 60)], action: "action1").size).to eq 1
        expect(app.metrics([base_time, base_time + (60 * 60)], action: "action2").size).to eq 1
        expect(app.metrics([base_time, base_time + (60 * 60)]).size).to eq 1
      ensure
        SpartanAPM.max_actions = save_val
        app.clear!([base_time, base_time + (61 * 60)])
      end
    end

    it "should store stats for the last day", freeze_time: true do
      app = SpartanAPM::Persistence.new("app")
      base_time = Time.utc(2022, 2, 22, 0, 0)
      app.delete_hourly_stats!
      app.delete_daily_stats!
      begin
        25.times do |hour|
          measure = SpartanAPM::Measure.new("app", "action")
          measure.capture_time("app", 0.01 * (hour + 1))
          measure.capture_time("database", 0.02 * (hour + 1))
          measure.capture_error(ArgumentError.new) if hour % 4 == 0
          bucket = SpartanAPM.bucket(base_time + (hour * 60 * 60))
          SpartanAPM::Persistence.store!(bucket, [measure])
        end
        metrics = app.daily_metrics(base_time)
        expect(metrics.size).to eq 1
        metric = metrics.first
        expect(metric.time).to eq base_time
        expect(metric.count).to eq 24
        expect(metric.error_count).to eq 6
        expect(metric.components.collect { |k, vals| [k, vals.collect { |v| v.round(3) }] }).to eq({"app" => [125, 0.017], "database" => [250, 0.017]}.to_a)
        expect(metric.avg).to eq 375
        expect(metric.p50).to eq 375
        expect(metric.p90).to eq 375
        expect(metric.p99).to eq 375
      ensure
        app.clear!([base_time, base_time + (25 * 60 * 60)])
      end
    end
  end

  describe "hosts" do
    it "should get a list of all hosts" do
      measure_1 = SpartanAPM::Measure.new("app", "action_1")
      measure_2 = SpartanAPM::Measure.new("app", "action_2")
      measure_3 = SpartanAPM::Measure.new("app", "action_3")
      measure_1.timers["test"] = 1.0
      measure_2.timers["test"] = 2.0
      measure_3.timers["test"] = 3.0
      time = Time.now
      begin
        allow(SpartanAPM).to receive(:host).and_return("testhost_1")
        SpartanAPM::Persistence.store!(SpartanAPM.bucket(time), [measure_1])
        SpartanAPM::Persistence.store!(SpartanAPM.bucket(time), [measure_2])
        allow(SpartanAPM).to receive(:host).and_return("testhost_2")
        SpartanAPM::Persistence.store!(SpartanAPM.bucket(time), [measure_3])
        expect(SpartanAPM::Persistence.new("app").hosts(time)).to match_array(["testhost_1", "testhost_2"])
        expect(SpartanAPM::Persistence.new("app").hosts(time, action: "action_1")).to match_array(["testhost_1"])
        expect(SpartanAPM::Persistence.new("app").hosts(time, action: "action_3")).to match_array(["testhost_2"])
      ensure
        SpartanAPM::Persistence.new("app").clear!(time)
      end
    end
  end

  describe "actions" do
    it "should get a list of all actions with the total time spent percentage", freeze_time: true do
      measure_1 = SpartanAPM::Measure.new("app", "action_1")
      measure_2 = SpartanAPM::Measure.new("app", "action_2")
      measure_3 = SpartanAPM::Measure.new("app", "action_3")
      measure_1.timers["test"] = 1.0
      measure_2.timers["test"] = 2.0
      measure_3.timers["test"] = 3.0
      time = Time.now
      begin
        SpartanAPM::Persistence.store!(SpartanAPM.bucket(time), [measure_1, measure_2, measure_2, measure_3])
        actions = SpartanAPM::Persistence.new("app").actions([time, time])
        expect(actions).to eq([["action_2", 0.5], ["action_3", 0.375], ["action_1", 0.125]])

        actions = SpartanAPM::Persistence.new("app").actions([time, time], limit: 2)
        expect(actions).to eq([["action_2", 0.5], ["action_3", 0.375]])
      ensure
        SpartanAPM::Persistence.new("app").clear!(time)
      end
    end
  end

  describe "average_process_count" do
    it "should return the average number of processes reporting during a time range"
  end

  describe "errors" do
    it "should store aggregated error info" do
      time = Time.now
      bucket_1 = SpartanAPM.bucket(time)
      bucket_2 = SpartanAPM.bucket(time + 60)
      measures_1 = []
      begin
        raise ArgumentError.new("error other")
      rescue => e
        m = SpartanAPM::Measure.new("app", "action")
        m.capture_error(e)
        measures_1 << m
      end
      measures_1 << SpartanAPM::Measure.new("app", "action")

      measures_2 = []
      3.times do |i|
        begin
          if i.zero?
            raise StandardError.new("error #{i}")
          else
            raise ArgumentError.new("error #{i}")
          end
        rescue => e
          m = SpartanAPM::Measure.new("app", "action")
          m.capture_error(e)
          measures_2 << m
        end
      end
      measures_2 << SpartanAPM::Measure.new("app", "action")

      begin
        SpartanAPM::Persistence.store!(bucket_1, measures_1)
        SpartanAPM::Persistence.store!(bucket_2, measures_2)

        errors = SpartanAPM::Persistence.new("app").errors([time, time + 60])
        data = errors.collect { |e| [e.time, e.class_name, e.message, e.count, e.backtrace] }
        expect(data).to match_array [
          [SpartanAPM.bucket_time(bucket_1), "ArgumentError", "error other", 1, measures_1.first.error_backtrace],
          [SpartanAPM.bucket_time(bucket_2), "StandardError", "error 0", 1, measures_2.first.error_backtrace],
          [SpartanAPM.bucket_time(bucket_2), "ArgumentError", "error 1", 2, measures_2[1].error_backtrace]
        ]

        expect(SpartanAPM::Persistence.new("app").errors([time, time]).collect(&:count)).to eq [1]
      ensure
        SpartanAPM::Persistence.new("app").clear!([time, time + 60])
      end
    end
  end
end
