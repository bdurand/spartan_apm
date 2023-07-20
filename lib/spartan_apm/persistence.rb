# frozen_string_literal: true

module SpartanAPM
  class Persistence
    STORE_STATS_SCRIPT = <<~LUA
      local key = KEYS[1]
      local actions_key = KEYS[2]

      local action = ARGV[1]
      local host = ARGV[2]
      local data = cjson.decode(ARGV[3])
      local total_time = tonumber(ARGV[4])
      local ttl = tonumber(ARGV[5])

      local host_stats = nil
      local host_stats_data = redis.call('hget', key, host)
      if host_stats_data then
        host_stats = cmsgpack.unpack(host_stats_data)
      else
        host_stats = {}
      end
      for name, values in pairs(data) do
        local name_stats = host_stats[name]
        if name_stats == nil then
          name_stats = {}
          host_stats[name] = name_stats
        end
        name_stats[#name_stats + 1] = values
      end
      redis.call('hset', key, host, cmsgpack.pack(host_stats))
      redis.call('zincrby', actions_key, total_time, action)
      redis.call('expire', key, ttl)
      redis.call('expire', actions_key, ttl)
    LUA

    MAX_KEEP_AGGREGATED_STATS = 365 * 24 * 60 * 60

    # Key used to store aggregated values for all components
    ALL_COMPONENTS = "."

    class << self
      def store!(bucket, measures)
        store_measure_stats(bucket, measures)
        store_measure_errors(bucket, measures)
        measures.collect(&:app).uniq.each do |app|
          store_hour_stats(app, bucket)
          store_day_stats(app, bucket)
        end
      end

      # Truncate a time to the hour (UTC time).
      # @param time [Time]
      # @return [Time]
      def truncate_to_hour(time)
        time = Time.at(time.to_f).utc
        Time.utc(time.year, time.month, time.day, time.hour)
      end

      # Truncate a time to the date (UTC time).
      # @param time [Time]
      # @return [Time]
      def truncate_to_date(time)
        time = Time.at(time.to_f).utc
        Time.utc(time.year, time.month, time.day)
      end

      private

      def redis_key(env, app, action, bucket)
        app = app.to_s.tr("~", "-")
        action = action.to_s
        action = "~#{action}" unless action.empty?
        "SpartanAPM:metrics:#{env}:#{bucket}:#{app}#{action}"
      end

      def actions_key(env, app, bucket)
        "SpartanAPM:actions:#{env}:#{bucket}:#{app}"
      end

      def errors_key(env, app, bucket)
        "SpartanAPM:errors:#{env}:#{bucket}:#{app}"
      end

      def hours_key(env, app)
        "SpartanAPM:hours:#{env}:#{app}"
      end

      def days_key(env, app)
        "SpartanAPM:days:#{env}:#{app}"
      end

      def hours_semaphore(env, app, hour)
        "SpartanAPM:hours_semaphore:#{env}:#{hour}:#{app}"
      end

      def days_semaphore(env, app, day)
        "SpartanAPM:days_semaphore:#{env}:#{day}:#{app}"
      end

      def store_measure_stats(bucket, measures)
        start_time = SpartanAPM.clock_time
        action_values = {}
        measures.each do |measure|
          next if measure.timers.empty?
          aggregate_values(action_values, [measure.app, measure.action], measure)
          if measure.action
            aggregate_values(action_values, [measure.app, nil], measure)
          end
        end

        action_values.each do |action_key, action_measures|
          app, action = action_key
          data = aggregate_stats(action_measures)
          store_metric(bucket, app, action, SpartanAPM.host, data)
        end

        SpartanAPM.logger&.info("SpartanAPM stored #{action_values.size} stats in #{((SpartanAPM.clock_time - start_time) * 1000).round}ms")
      end

      def aggregate_values(map, key, value)
        values = map[key]
        unless values
          values = []
          map[key] = values
        end
        values << value
      end

      def aggregate_stats(measures)
        times = {}
        counts = Hash.new(0)
        total_times = []
        error_count = 0
        measures.each do |measure|
          total_times << measure.timers.values.sum
          error_count += 1 if measure.error
          measure.timers.each do |name, value|
            aggregate_values(times, name, value)
          end
          measure.counts.each do |name, value|
            counts[name] += value.to_f
          end
        end

        stats = {}
        times.each do |name, values|
          elapsed_time = (values.sum * 1000).round
          stats[name.to_s] = [measures.size, elapsed_time, counts[name]]
        end

        count = (measures.size.to_f / SpartanAPM.sample_rate).round
        total_times.sort!
        time = ((total_times.sum * 1000).round / SpartanAPM.sample_rate).round
        p50 = (total_times[(total_times.size * 0.5).floor] * 1000).round
        p90 = (total_times[(total_times.size * 0.90).floor] * 1000).round
        p99 = (total_times[(total_times.size * 0.99).floor] * 1000).round
        errors = (error_count / SpartanAPM.sample_rate).round
        stats[ALL_COMPONENTS] = [count, time, p50, p90, p99, errors]

        stats
      end

      def store_metric(bucket, app, action, host, data)
        script_keys = [redis_key(SpartanAPM.env, app, action, bucket), actions_key(SpartanAPM.env, app, bucket)]
        script_args = [action, host, JSON.dump(data), data[ALL_COMPONENTS][1], SpartanAPM.ttl]
        eval_script(STORE_STATS_SCRIPT, script_keys, script_args)
      end

      def store_measure_errors(bucket, measures)
        start_time = SpartanAPM.clock_time
        errors = {}
        measures.each do |measure|
          next unless measure.error

          error_key = Digest::MD5.hexdigest("#{measure.error} #{measure.error_backtrace&.join}")
          app_errors = errors[measure.app]
          unless app_errors
            app_errors = {}
            errors[measure.app] = app_errors
          end
          error_info = app_errors[error_key]
          unless error_info
            error_info = [measure.error, measure.error_message, measure.error_backtrace, 0]
            app_errors[error_key] = error_info
          end
          error_info[3] += 1
        end

        errors.each do |app, app_errors|
          app_errors.each do |error_key, info|
            class_name, message, backtrace, count = info
            store_error(bucket, app, class_name, message, backtrace, count)
          end
        end

        SpartanAPM.logger&.info("SpartanAPM stored #{errors.size} errors in #{((SpartanAPM.clock_time - start_time) * 1000).round}ms")
      end

      def store_error(bucket, app, class_name, message, backtrace, count)
        key = errors_key(SpartanAPM.env, app, bucket)
        payload = deflate(MessagePack.dump([class_name, message, backtrace]))
        SpartanAPM.redis.multi do |transaction|
          transaction.zincrby(key, count.round, payload)
          transaction.expire(key, SpartanAPM.ttl)
        end
      end

      def store_hour_stats(app, bucket)
        redis = SpartanAPM.redis
        hour = truncate_to_hour(SpartanAPM.bucket_time(bucket - 60)).to_i
        hour_exists = redis.zrangebyscore(hours_key(SpartanAPM.env, app), hour, hour).first
        return if hour_exists

        semaphore = hours_semaphore(SpartanAPM.env, app, hour)
        locked, _ = redis.multi do |transaction|
          transaction.setnx(semaphore, "1")
          transaction.expire(semaphore, 60)
        end
        return unless locked

        begin
          stats = hour_stats(app, hour)
          unless stats.empty?
            add_hourly_stats(app, stats)
            base_bucket = SpartanAPM.bucket(Time.at(hour))
            60.times do |minute|
              truncate_actions!(app, base_bucket + minute)
            end
          end
        ensure
          redis.del(semaphore)
        end
      end

      def store_day_stats(app, bucket)
        redis = SpartanAPM.redis
        day = truncate_to_date(SpartanAPM.bucket_time(bucket - (60 * 24))).to_i
        day_exists = redis.zrangebyscore(days_key(SpartanAPM.env, app), day, day).first
        return if day_exists

        semaphore = days_semaphore(SpartanAPM.env, app, day)
        locked, _ = redis.multi do |transaction|
          transaction.setnx(semaphore, "1")
          transaction.expire(semaphore, 60)
        end
        return unless locked

        begin
          stats = day_stats(app, day)
          add_daily_stats(app, stats) unless stats.empty?
        ensure
          redis.del(semaphore)
        end
      end

      def hour_stats(app, hour)
        report = Report.new(app, Time.at(hour), Time.at(hour + (59 * 60)))
        error_count = 0
        count = 0
        report.each_time do |time|
          error_count += report.error_count(time)
          count += report.request_count(time)
        end
        components = {}
        report.component_names.each do |name|
          components[name] = [report.avg_component_time(name), report.avg_component_count(name)]
        end
        {
          hour: hour,
          components: components,
          avg: report.avg_request_time(:avg),
          p50: report.avg_request_time(:p50),
          p90: report.avg_request_time(:p90),
          p99: report.avg_request_time(:p99),
          error_count: error_count,
          count: count
        }
      end

      def day_stats(app, day)
        last_hour = day + (60 * 60 * 23)
        hour_stats = SpartanAPM.redis.zrangebyscore(hours_key(SpartanAPM.env, app), day, last_hour).collect { |data| MessagePack.load(data) }
        return [] if hour_stats.empty?

        if hour_stats.last["hour"] != last_hour
          next_stat = SpartanAPM.redis.zrevrange(hours_key(SpartanAPM.env, app), 0, 1).first
          if next_stat && MessagePack.load(next_stat)["hour"] < last_hour
            return []
          end
        end

        components = {}
        avgs = []
        p50s = []
        p90s = []
        p99s = []
        count = 0
        error_count = 0
        hour_stats.each do |stat|
          request_count = stat["count"]
          next if request_count.nil?
          stat["components"].each do |name, values|
            timing, avg_count = values
            component_time, component_count = components[name]
            unless component_time
              component_time = 0
              component_count = 0.0
            end
            component_time += timing.to_f * request_count
            component_count += avg_count.to_f
            components[name] = [component_time, component_count]
          end
          avgs << stat["avg"] * request_count
          p50s << stat["p50"] * request_count
          p90s << stat["p90"] * request_count
          p99s << stat["p99"] * request_count
          count += request_count
          error_count += stat["error_count"]
        end
        aggregated_components = {}
        components.each do |name, values|
          weighted_timing, weighted_avg_count = values
          aggregated_components[name] = if count > 0
            [(weighted_timing / count).round, weighted_avg_count / hour_stats.size]
          else
            [0, 0.0]
          end
        end
        {
          day: day,
          components: aggregated_components,
          avg: ((count > 0) ? (avgs.sum.to_f / count).round : 0),
          p50: ((count > 0) ? (p50s.sum.to_f / count).round : 0),
          p90: ((count > 0) ? (p90s.sum.to_f / count).round : 0),
          p99: ((count > 0) ? (p99s.sum.to_f / count).round : 0),
          error_count: error_count,
          count: count
        }
      end

      def add_hourly_stats(app, stats)
        key = hours_key(SpartanAPM.env, app)
        hour = (stats["hour"] || stats[:hour])
        SpartanAPM.redis.multi do |transaction|
          transaction.zremrangebyscore(key, hour, hour)
          transaction.zadd(key, hour, MessagePack.dump(stats))
          transaction.zremrangebyscore(key, "-inf", hour - MAX_KEEP_AGGREGATED_STATS)
          transaction.expire(key, MAX_KEEP_AGGREGATED_STATS)
        end
      end

      def add_daily_stats(app, stats)
        key = days_key(SpartanAPM.env, app)
        day = (stats["day"] || stats[:day])
        SpartanAPM.redis.multi do |transaction|
          transaction.zremrangebyscore(key, day, day)
          transaction.zadd(key, day, MessagePack.dump(stats))
          transaction.zremrangebyscore(key, "-inf", day - MAX_KEEP_AGGREGATED_STATS)
          transaction.expire(key, MAX_KEEP_AGGREGATED_STATS)
        end
      end

      def truncate_actions!(app, bucket)
        action_key = actions_key(SpartanAPM.env, app, bucket)
        min_used_actions = SpartanAPM.redis.zrevrange(action_key, SpartanAPM.max_actions + 1, -1)
        min_used_actions.delete(ALL_COMPONENTS)
        return if min_used_actions.empty?
        min_used_actions.each do |action|
          SpartanAPM.redis.multi do |transaction|
            transaction.zrem(action_key, action)
            transaction.del(redis_key(SpartanAPM.env, app, action, bucket))
          end
        end
      end

      def deflate(string)
        Zlib::Deflate.deflate(string, Zlib::DEFAULT_COMPRESSION)
      end

      def eval_script(script, keys, args)
        script_sha = Digest::SHA1.hexdigest(script)
        attempts = 0
        redis = SpartanAPM.redis
        begin
          redis.evalsha(script_sha, Array(keys).collect(&:to_s), Array(args).collect(&:to_s))
        rescue Redis::CommandError => e
          if e.message.include?("NOSCRIPT") && attempts < 2
            attempts += 1
            script_sha = redis.script(:load, script)
            retry
          else
            raise e
          end
        end
      end
    end

    def initialize(app, env: SpartanAPM.env)
      @app = app
      @env = env
    end

    def report_info(time_range, action: nil, host: nil)
      metrics = []
      host_summaries = {}
      read_range(time_range, action, host) do |bucket, metric_data, bucket_host_data|
        metric = metric_from_values(bucket, metric_data)
        metrics << metric if metric
        bucket_host_data.each do |hostname, host_data|
          host_summary = host_summaries[hostname]
          if host_summary
            host_summary[:requests] += host_data[:requests]
            host_summary[:time] += host_data[:time]
            host_summary[:errors] += host_data[:errors]
          else
            host_summaries[hostname] = host_data
          end
        end
      end
      [metrics, host_summaries]
    end

    def metrics(time_range, action: nil, host: nil)
      report_info(time_range, action: action, host: host).first
    end

    def hourly_metrics(time_range)
      read_aggregated_metrics(:hour, time_range)
    end

    def daily_metrics(time_range)
      read_aggregated_metrics(:day, time_range)
    end

    def errors(time_range)
      backtrace_cache = {}
      errors = []
      empty_backtrace = [].freeze
      redis = SpartanAPM.redis
      each_bucket(time_range) do |bucket|
        key = errors_key(bucket)
        redis.zrevrange(key, 0, 99, withscores: true).each do |payload, count|
          class_name, message, raw_backtrace = MessagePack.load(Zlib::Inflate.inflate(payload))
          backtrace = empty_backtrace
          if raw_backtrace
            backtrace_key = Digest::MD5.hexdigest(raw_backtrace.join("\n"))
            backtrace = backtrace_cache[backtrace_key]
            if backtrace.nil? && !raw_backtrace.nil?
              backtrace = raw_backtrace.freeze
              backtrace_cache[backtrace_key] = backtrace
            end
          end
          errors << ErrorInfo.new(SpartanAPM.bucket_time(bucket), class_name, message, backtrace, count)
        end
      end
      errors
    end

    def actions(time_range, limit: 100, interval: 1)
      action_times = Hash.new(0.0)
      total_time = 0.0
      redis = SpartanAPM.redis
      each_bucket(time_range, interval: interval) do |bucket|
        redis.zrevrange(actions_key(bucket), 0, limit, withscores: true).each do |action, time_spent|
          if action == ""
            total_time += time_spent
          else
            action_times[action] += time_spent
          end
        end
      end
      actions = {}
      action_times.each do |action, time_spent|
        actions[action] = ((total_time > 0) ? time_spent / total_time : 0.0)
      end
      actions.sort_by { |action, time_spent| -time_spent }.take(limit)
    end

    def hosts(time_range, action: nil)
      uniq_hosts = Set.new
      redis = SpartanAPM.redis
      each_bucket(time_range) do |bucket|
        redis.hkeys(redis_key(action, bucket)).each do |host|
          uniq_hosts << host
        end
      end
      uniq_hosts.to_a.sort
    end

    # Return the average number of processes reporting data during the time range.
    # You can use this data in a custom monitor to determine process counts by host.
    # @param time_range [Time, Enumerable<Time>] The time range to process.
    # @param host [String] Optional host name to filter on.
    # @return [Integer]
    def average_process_count(time_range, host: nil)
      bucket_counts = []
      each_bucket(time_range) do |bucket|
        count = 0
        read_host_data(bucket, nil, host) do |hostname, data|
          count += data[ALL_COMPONENTS].size
        end
        bucket_counts << count if count > 0
      end
      return 0 if bucket_counts.empty?
      (bucket_counts.sum.to_f / bucket_counts.size).round
    end

    def clear!(time_range)
      clear_minute_stats!(time_range)
      clear_hourly_stats!(time_range)
      clear_daily_stats!(time_range)
    end

    def clear_minute_stats!(time_range)
      redis = SpartanAPM.redis
      each_bucket(time_range) do |bucket|
        action_key = actions_key(bucket)
        actions = redis.zrevrange(action_key, 0, 1_000_000)
        keys = (actions + [ALL_COMPONENTS]).collect { |action| redis_key(action, bucket) }
        redis.del(keys + [action_key, errors_key(bucket)])
      end
    end

    def clear_hourly_stats!(time_range)
      time_range = [time_range] unless time_range.respond_to?(:last)
      start_hour_bucket = self.class.truncate_to_hour(time_range.first).to_f
      end_hour_bucket = self.class.truncate_to_hour(time_range.last).to_f
      SpartanAPM.redis.zremrangebyscore(hours_key, start_hour_bucket, end_hour_bucket)
    end

    def clear_daily_stats!(time_range)
      time_range = [time_range] unless time_range.respond_to?(:last)
      start_date_bucket = self.class.truncate_to_date(time_range.first).to_f
      end_date_bucket = self.class.truncate_to_hour(time_range.last).to_f
      SpartanAPM.redis.zremrangebyscore(days_key, start_date_bucket, end_date_bucket)
    end

    def delete_hourly_stats!
      SpartanAPM.redis.del(hours_key)
    end

    def delete_daily_stats!
      SpartanAPM.redis.del(days_key)
    end

    private

    def redis_key(action, bucket)
      self.class.send(:redis_key, @env, @app, action, bucket)
    end

    def actions_key(bucket)
      self.class.send(:actions_key, @env, @app, bucket)
    end

    def errors_key(bucket)
      self.class.send(:errors_key, @env, @app, bucket)
    end

    def hours_key
      self.class.send(:hours_key, @env, @app)
    end

    def days_key
      self.class.send(:days_key, @env, @app)
    end

    def actions_at(bucket)
      SpartanAPM.redis.zrevrange(actions_key(bucket), 0, 1_000_000)
    end

    def metric_from_values(bucket, combined_data)
      metric = Metric.new(SpartanAPM.bucket_time(bucket))

      totals = combined_data.delete(ALL_COMPONENTS)
      return metric if totals.nil?

      metric.count = totals.sum(&:first) if totals
      return metric if metric.count == 0

      times = []
      p50s = []
      p90s = []
      p99s = []
      error_count = 0
      totals.each do |values|
        count = values[0]
        weight = count.to_f / metric.count.to_f
        times << (values[1] * weight) * totals.size
        p50s << values[2]
        p90s << values[3]
        p99s << values[4]
        error_count += values[5].to_i
      end
      metric.avg = (times.compact.sum.to_f / metric.count).round
      metric.p50 = (p50s.compact.sum.to_f / p50s.size).round
      metric.p90 = (p90s.compact.sum.to_f / p90s.size).round
      metric.p99 = (p99s.compact.sum.to_f / p99s.size).round
      metric.error_count = error_count

      combined_data.each do |name, component_times|
        weighted_component_times = []
        weighted_component_counts = []
        component_times.each do |component_count, component_time, call_count|
          weight = component_count.to_f / metric.count.to_f
          weighted_component_times << (component_time * weight) * totals.size
          weighted_component_counts << (call_count * weight) * totals.size
        end
        metric.components[name] = [(weighted_component_times.sum.to_f / metric.count).round, weighted_component_counts.sum.to_f / metric.count]
      end

      metric
    end

    def each_bucket(time_range, interval: 1, &block)
      start_time = (time_range.is_a?(Enumerable) ? time_range.first : time_range)
      end_time = (time_range.is_a?(Enumerable) ? time_range.last : time_range)
      start_bucket = SpartanAPM.bucket(start_time)
      end_bucket = SpartanAPM.bucket(end_time)
      (start_bucket..end_bucket).step(interval).each(&block)
    end

    def read_range(time_range, action, host)
      each_bucket(time_range) do |bucket|
        host_summaries = {}
        combined_data = {}
        read_host_data(bucket, action, host) do |hostname, data|
          data.each do |name, values|
            combined_values = combined_data[name]
            unless combined_values
              combined_values = []
              combined_data[name] = combined_values
            end
            combined_values.concat(values)

            if name == ALL_COMPONENTS
              host_summary = host_summaries[hostname]
              unless host_summary
                host_summary = {requests: 0, errors: 0, time: 0}
                host_summaries[hostname] = host_summary
              end
              host_summary[:requests] += values.sum { |vals| vals[0] }
              host_summary[:time] += values.sum { |vals| vals[1] }
              host_summary[:errors] += values.sum { |vals| vals[5] }
            end
          end
        end

        unless combined_data.empty?
          yield(bucket, combined_data, host_summaries)
        end
      end
    end

    def read_host_data(bucket, action, host)
      redis = SpartanAPM.redis
      key = redis_key(action, bucket)
      host_data = (host ? {host => redis.hget(key, host)} : redis.hgetall(key))
      host_data.each do |hostname, packed_data|
        next if packed_data.nil?
        data = MessagePack.load(packed_data)
        yield(hostname, data)
      end
    end

    def read_aggregated_metrics(unit, time_range)
      key = ((unit == :hour) ? hours_key : days_key)
      start_time = Time.at((time_range.respond_to?(:first) ? time_range.first : time_range).to_f)
      end_time = Time.at((time_range.respond_to?(:last) ? time_range.last : time_range).to_f)

      if unit == :hour
        start_time = self.class.truncate_to_hour(start_time)
        end_time = self.class.truncate_to_hour(end_time)
      else
        start_time = self.class.truncate_to_date(start_time)
        end_time = self.class.truncate_to_date(end_time)
      end

      SpartanAPM.redis.zrangebyscore(key, start_time.to_f, end_time.to_f).collect do |raw_data|
        data = MessagePack.load(raw_data)
        time = Time.at(data[unit.to_s]).utc
        metric = Metric.new(time)
        metric.count = data["count"]
        metric.error_count = data["error_count"]
        metric.components = data["components"]
        metric.avg = data["avg"]
        metric.p50 = data["p50"]
        metric.p90 = data["p90"]
        metric.p99 = data["p99"]
        metric
      end
    end
  end
end
