# frozen_string_literal: true

module SpartanAPM
  module Web
    # Wrapper for API requests.
    class ApiRequest
      attr_reader :request

      def initialize(request)
        @request = request
      end

      # Response for /metrics
      def metrics
        report = create_report
        component_data = {}
        report.component_names.each do |name|
          component_data[name] = {
            time: report.collect { |time| report.component_request_time(time, name) },
            count: report.collect { |time| report.component_request_count(time, name).round(1) }
          }
        end
        {
          env: report.env,
          app: report.app,
          host: report.host,
          action: report.action,
          hosts: report.hosts,
          actions: report.actions,
          minutes: report.minutes,
          interval_minutes: report.interval_minutes,
          times: report.collect { |time| time.iso8601 },
          avg: {
            avg: report.avg_request_time(:avg),
            data: component_data
          },
          p50: {
            avg: report.avg_request_time(:p50),
            data: report.collect { |time| report.request_time(time, :p50) }
          },
          p90: {
            avg: report.avg_request_time(:p90),
            data: report.collect { |time| report.request_time(time, :p90) }
          },
          p99: {
            avg: report.avg_request_time(:p99),
            data: report.collect { |time| report.request_time(time, :p99) }
          },
          throughput: {
            avg: report.avg_requests_per_minute,
            data: report.collect { |time| report.requests_per_minute(time) }
          },
          errors: {
            avg: report.avg_errors_per_minute,
            data: report.collect { |time| report.error_count(time) }
          },
          error_rate: {
            avg: report.avg_error_rate,
            data: report.collect { |time| report.error_rate(time) }
          }
        }
      end

      # Response for /live_metrics
      def live_metrics
        begin
          current_bucket = SpartanAPM.bucket(Time.now - 65)
          last_bucket = SpartanAPM.bucket(Time.parse(param(:live_time)))
          return({}) if current_bucket <= last_bucket
        rescue
          return({})
        end
        metrics
      end

      # Response for /errors
      def errors
        report = create_report
        {
          errors: report.errors.collect { |error| {class_name: error.class_name, message: error.message, count: error.count, backtrace: error.backtrace} }
        }
      end

      # Response for /actions
      def actions
        report = create_report
        {
          actions: report.actions.collect { |action| {name: action, load: report.action_percent_time(action)} }
        }
      end

      private

      def param(name, default: nil)
        value = request.params[name.to_s]
        if value.nil? || value == ""
          value = default&.to_s
        end
        value
      end

      def create_report
        env = (param(:env) || SpartanAPM.env)
        env = SpartanAPM.env unless SpartanAPM.environments.include?(env)
        app = param(:app)
        action = param(:action)
        host = param(:host)
        minutes = param(:minutes).to_i
        minutes = 30 if minutes <= 0
        minutes = 60 * 24 * 365 if minutes > 60 * 24 * 365
        start_time = nil
        time = param(:time)
        if time
          begin
            start_time = Time.parse(time)
          rescue
            # Use default
          end
        end
        if start_time.nil?
          interval_minutes = Report.interval_minutes(minutes)
          start_time = if interval_minutes < 60
            Time.now - (minutes * 60)
          else
            Time.now - ((interval_minutes * 60) + (minutes * 60))
          end
        end
        end_time = start_time + ((minutes - 1) * 60)
        Report.new(app, start_time, end_time, host: host, action: action, env: env)
      end
    end
  end
end
