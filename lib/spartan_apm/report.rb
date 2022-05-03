# frozen_string_literal: true

module SpartanAPM
  # This is the main interface for reading the APM metrics. It will expose
  # a list of metrics and errors from a given time period. The report can also
  # be filtered by action and/or host.
  #
  # You can use this class to query the APM metrics if you want to construct
  # your own interface or create custom monitors.
  #
  # The metrics in the report are averaged and grouped over a number of minutes. This
  # number is set in the `interver_minutes` attribute and it increases as the time range
  # of the report increases. The time range for each interval is referred to as the
  # interval time.
  #
  # Loading the report metrics, errors, and actions will each send a request to Redis
  # for each minute in the time range. At larger interval times, hourly or daily aggregated
  # metrics are used and hosts, actions, and errors are not available.
  #
  # The end time for the report must be at least one minute in the past since metrics are
  # queued up before they are persisted to Redis so there will always be at least a one
  # minute lag.
  class Report
    attr_reader :env, :app, :start_time, :end_time, :minutes, :interval_minutes, :host, :action

    class << self
      def interval_minutes(minutes)
        if minutes <= 60
          1
        elsif minutes <= 2 * 60
          2
        elsif minutes <= 4 * 60
          5
        elsif minutes <= 12 * 60
          10
        elsif minutes <= 14 * 24 * 60
          60
        else
          60 * 24
        end
      end
    end

    # @param app [String, Symbol] The app name to get metrics for.
    # @param start_time [Time] The start time for the report (inclusive).
    # @param end_time [Time] The end time for the report (inclusive).
    # @param host [String] Optional host name to filter the metrics.
    # @param action [String] Optional action name to filter the metrics.
    # @param actions_limit [Integer] Limit on how many actions to pull from Redis.
    def initialize(app, start_time, end_time, host: nil, action: nil, actions_limit: 100, env: SpartanAPM.env)
      @app = app.to_s.dup.freeze
      @env = env.to_s.dup.freeze
      @start_time = normalize_time(start_time)
      @end_time = normalize_time(end_time)
      @end_time = @start_time if @end_time < @start_time

      @minutes = ((@end_time - @start_time) / 60).to_i + 1
      @interval_minutes = self.class.interval_minutes(@minutes)
      if !aggregated? && @start_time < Time.now - SpartanAPM.ttl
        @interval_minutes = 60 unless SpartanAPM.env == "test"
      end
      @end_time += (60 * (@minutes % @interval_minutes))

      @host = host&.dup.freeze
      @action = action&.dup.freeze
      @actions_limit = [actions_limit, SpartanAPM.max_actions].min
      @metrics = nil
      @actions = nil
      @errors = nil
    end

    # Returns true if using aggregated metrics averaged over an hour or day
    # @return [Boolean]
    def aggregated?
      interval_minutes >= 60
    end

    # Returns true if using hourly aggregated metrics
    # @return [Boolean]
    def aggregated_to_hour?
      interval_minutes == 60
    end

    # Returns true if using daily aggregated metrics
    # @return [Boolean]
    def aggregated_to_day?
      interval_minutes > 60
    end

    # Iterate over each time segment in the report. Yields the start time
    # for each segment.
    def each_time
      time = start_time
      while time <= end_time
        yield time
        time += 60 * interval_minutes
      end
    end

    # Collects a value for each time segment in the report. Yields the start
    # time for each segment and returns and array of the return values from the block.
    def collect
      list = []
      each_time do |time|
        list << yield(time)
      end
      list
    end

    # Get a Metric from a given time in the report.
    # @param time [Time] The time to get the metric for.
    # @return [SpartanAPM::Metric]
    def metric(time)
      load_metrics
      @metrics[normalize_time(time)] || Metric.new(time)
    end

    # Get the average request time taken in milliseconds for the named component at a time interval.
    # @param time [Time] The interval time.
    # @param name [String, Symbol] The component to get the value for.
    # @return [Integer]
    def component_request_time(time, name)
      value = 0.0
      count = 0
      each_interval(time) do |t|
        value += metric(t).component_request_time(name).to_f
        count += 1
      end
      (value / count).round
    end

    # Get the average number of calls per request for the named component.
    # @param time [Time] The interval time.
    # @param name [String, Symbol] The component to get the value for.
    # @return [Integer]
    def component_request_count(time, name)
      value = 0.0
      count = 0
      each_interval(time) do |t|
        value += metric(t).component_request_count(name).to_f
        count += 1
      end
      value / count
    end

    # Get the average total time taken in milliseconds for a request at a time interval.
    # @param time [Time] The interval time.
    # @param measurement [String, Symbol] The measurement to get. This must be one of :avg, :p50, :p90, or :p99.
    # @return [Integer]
    def request_time(time, measurement)
      value = 0.0
      count = 0
      each_interval(time) do |t|
        value += metric(t).send(measurement).to_f
        count += 1
      end
      (value / count).round
    end

    # Get the average time in milliseconds taken for a component for the report time range.
    # @param name [String, Symbol] The component name to get.
    # @return [Integer]
    def avg_component_time(name)
      total = 0
      count = 0
      each_time do |time|
        each_interval(time) do |t|
          value = metric(t).component_request_time(name)
          if value
            count += 1
            total += value.to_f
          end
        end
      end
      return 0 if count == 0
      (total / count).round
    end

    # Get the average time in milliseconds taken for a component for the report time range.
    # @param name [String, Symbol] The component name to get.
    # @return [Integer]
    def avg_component_count(name)
      total = 0.0
      count = 0
      each_time do |time|
        each_interval(time) do |t|
          m = metric(t)
          count += 1
          total += m.component_request_count(name).to_f
        end
      end
      return 0 if count == 0
      total / count
    end

    # Get the average time in milliseconds taken for a measurement for the report time range.
    # @param measurement [String, Symbol] The measurement to get. This must be one of :avg, :p50, :p90, or :p99.
    # @return [Integer]
    def avg_request_time(measurement)
      total = 0
      count = 0
      each_time do |time|
        each_interval(time) do |t|
          value = metric(t)&.send(measurement)
          if value
            count += 1
            total += value.to_f
          end
        end
      end
      return 0 if count == 0
      (total / count).round
    end

    # Get the total number of requests for a time interval.
    # @param time [Time] The interval time.
    # @return [Integer]
    def request_count(time)
      count = 0
      each_interval(time) do |t|
        count += metric(t)&.count.to_i
      end
      count
    end

    # Get the average number of requests per minute for a time interval.
    # @param time [Time] The interval time.
    # @return [Integer]
    def requests_per_minute(time)
      (request_count(time).to_f / interval_minutes).round
    end

    # Get the average requests per minute for the report time range.
    # @return [Integer]
    def avg_requests_per_minute
      total = 0.0
      count = 0
      each_time do |time|
        count += 1
        each_interval(time) do |t|
          total += metric(t)&.count.to_f
        end
      end
      if count > 0
        ((total / count) / interval_minutes).round
      else
        0
      end
    end

    # Get the number of errors reported for a time interval.
    # @param time [Time] The interval time.
    # @return [Integer]
    def error_count(time)
      total = 0
      each_interval(time) do |t|
        total += metric(t)&.error_count.to_i
      end
      total
    end

    # Get the average number of errors per minute for the report time range.
    # @return [Integer]
    def avg_errors_per_minute
      total = 0.0
      count = 0
      each_time do |time|
        each_interval(time) do |t|
          error_count = metric(t)&.error_count
          if error_count
            count += 1
            total += error_count
          end
        end
      end
      if count > 0
        (total.to_f / count).round(2)
      else
        0.0
      end
    end

    # Get the average of error rate (errors per request) for a time interval.
    # @param time [Time] The interval time.
    # @return [Float]
    def error_rate(time)
      count = request_count(time)
      if count > 0
        error_count(time).to_f / count.to_f
      else
        0.0
      end
    end

    # Get the average error rate (errors per request) for the report time range.
    # @return [Float]
    def avg_error_rate
      total_rate = 0.0
      count = 0
      each_time do |time|
        count += 1
        total_rate += error_rate(time)
      end
      if count > 0
        total_rate / count
      else
        0.0
      end
    end

    # Get the list of errors reported during the report time range.
    # @return [Array<SpartanAPM::ErrorInfo]
    def errors
      load_errors
      all_errors = {}
      @errors.values.each do |time_errors|
        time_errors.each do |error_info|
          key = [error_info.class_name, error_info.backtrace]
          err = all_errors[key]
          unless err
            err = ErrorInfo.new(nil, error_info.class_name, error_info.message, error_info.backtrace, 0)
            all_errors[key] = err
          end
          err.count += error_info.count
        end
      end
      all_errors.values.sort_by { |error_info| -error_info.count }
    end

    # Get the list of action names reported during the report time range. The returned
    # value is limited by the `actions_limit` argument passed in the constructor. The
    # list will be sorted by the amount of time spent in each action with the most
    # heavily used actions coming first.
    # @return [Array<String>] List of action names.
    def actions
      load_actions
      @actions.keys
    end

    # The the percent of time spent in the specified action.
    # @return [Float]
    def action_percent_time(action)
      load_actions
      @actions[action]
    end

    # Get the list of host names that reported metrics during the report time range.
    # @return [Array<String>]
    def hosts
      load_metrics
      @host_summaries.keys.sort
    end

    # Get a summary report of metrics broken down by host.
    # @return [Hash<String, Hash<String, Integer>>]
    def host_summaries
      load_metrics
      @host_summaries
    end

    # Get the list of component names that reported metrics during the report time range.
    # @return [Array<String>]
    def component_names
      load_metrics
      @names.sort
    end

    private

    # Lazily load the metric data.
    def load_metrics
      return if @metrics
      metrics_map = {}
      names = Set.new
      metrics = nil
      host_summaries = {}
      persistence = Persistence.new(app, env: env)
      if interval_minutes >= 60 * 24
        metrics = persistence.daily_metrics([start_time, end_time])
      elsif interval_minutes >= 60
        metrics = persistence.hourly_metrics([start_time, end_time])
      else
        metrics, host_summaries = persistence.report_info([start_time, end_time], host: host, action: action)
      end
      metrics.each do |metric|
        metric.component_names.each { |n| names << n }
        metrics_map[metric.time] = metric
      end
      @names = names.to_a.freeze
      @host_summaries = host_summaries.freeze
      @metrics = metrics_map
    end

    # Lazily load the action data.
    def load_actions
      return if @actions
      actions = {}
      unless aggregated?
        Persistence.new(app, env: env).actions([start_time, end_time], interval: interval_minutes, limit: @actions_limit).each do |action, load_val|
          actions[action] = load_val
        end
      end
      @actions = actions
    end

    # Lazily load the error data.
    def load_errors
      return if @errors
      errors = {}
      unless aggregated?
        Persistence.new(app, env: env).errors([start_time, end_time]).each do |error|
          time_errors = errors[error.time]
          unless time_errors
            time_errors = []
            errors[error.time] = time_errors
          end
          time_errors << error
        end
      end
      @errors = errors
    end

    def normalize_time(time)
      SpartanAPM.bucket_time(SpartanAPM.bucket(time)).freeze
    end

    def each_interval(time)
      time = normalize_time(time)
      if aggregated?
        time = if aggregated_to_hour?
          SpartanAPM::Persistence.truncate_to_hour(time)
        else
          SpartanAPM::Persistence.truncate_to_date(time)
        end
        yield(time)
      else
        interval_minutes.times do |interval|
          yield(time + (interval * 60))
        end
      end
    end
  end
end
