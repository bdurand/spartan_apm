# frozen_string_literal: true

require "set"
require "digest"
require "zlib"
require "time"
require "json"

require "redis"
require "msgpack"
require "concurrent-ruby"
require "rack"

module SpartanAPM
  DEFAULT_TTL = 60 * 60 * 24 * 7

  # These are the default locations of javascript and CSS assets.
  @plotly_js_url = ENV.fetch("SPARTAN_APM_PLOTLY_JS_URL", "https://cdn.plot.ly/plotly-basic-2.9.0.min.js")

  @ignore_patterns = {}

  @max_actions = 100

  class << self
    # The configure method is just syntactic sugar to call a block that yields this module.
    # ```
    # SpartanAPM.configure do |config|
    #   config.env = "production"
    #   config.sample_rate = 0.1
    # end
    # ```
    def configure
      yield self
    end

    # Set the environment name for the application. This can be used if you want to share
    # the same Redis server between different environments. For instance if you have multiple
    # staging environments, you could have them all share a single Redis rather than have to
    # stand up a dedicated one for each environment. The value can also be set with the
    # SPARTAN_APM_ENV environment variable.
    def env=(value)
      value = value.to_s.dup.freeze
      raise ArgumentError.new("env cannot contain a tilda") if value.include?("~")
      @_env_set = true
      @env = value
    end

    # @return [String] The environment name for the application.
    def env
      @env ||= ENV.fetch("SPARTAN_APM_ENV", "default")
    end

    # @api private
    def env_set?
      !!(defined?(@_env_set) && @_env_set)
    end

    # Set the list of available environments for the Web UI. This is only useful if there
    # are multiple environments being saved to the same Redis database.
    # @param value [Array<String>] List of environments.
    def environments=(value)
      @environments = Array(value).collect(&:to_s)
    end

    # Get the list of environments being tracked. This is used in the web UI to allow switching
    # between multiple environments that are being stored to the same Redis database.
    # @return [Array<String>] List of environments.
    def environments
      @environments ||= ENV.fetch("SPARTAN_APM_ENVIRONMENTS", env).split(/\s*,\s*/)
    end

    # Set the sample rate for monitoring. If your application gets a lot traffic, you
    # can use this setting to only record a percentage of it rather than every single
    # request. The value can also be set with the SPARTAN_APM_SAMPLE_RATE environment
    # variable
    def sample_rate=(value)
      @sample_rate = value&.to_f
    end

    # @return [Float] The sample rate for the application.
    def sample_rate
      @sample_rate ||= ENV.fetch("SPARTAN_APM_SAMPLE_RATE", "1.0").to_f
    end

    # Set the time to live in seconds for how long data will be stored in Redis.
    # The value can also be set with the SPARTAN_APM_TTL environment variable.
    def ttl=(value)
      value = value.to_i
      raise ArgumentError.new("ttl must be > 0") if value < 0
      @ttl = value
    end

    # @return [Integer] The time to live in seconds for how long data will be persisted in Redis.
    def ttl
      unless defined?(@ttl)
        value = ENV["SPARTAN_APM_TTL"].to_i
        value = DEFAULT_TTL if value <= 0
        @ttl = value
      end
      @ttl
    end

    # Maximum number of actions that will be tracked. If more actions than this are being
    # used by the application, then only the top most used actions by request time will
    # be tracked.
    attr_accessor :max_actions

    # Set a Logger object where events can be logged. You can set this if you want
    # to record how long it takes to persist the instrumentation data to Redis.
    attr_writer :logger

    # @return [Logger]
    def logger
      @logger = nil unless defined?(@logger)
      @logger
    end

    # Set an optional application name to show in the web UI.
    attr_writer :application_name

    def application_name
      @application_name ||= ENV.fetch("SPARTAN_APM_APPLICATION_NAME", "SpartanAPM")
    end

    # Set an option URL for a link in the web UI header.
    attr_accessor :application_url

    # URL for authenticating access to the application. This would normally be some kind of
    # login page. Browsers will be redirected here if they are denied access to the web UI.
    attr_accessor :authentication_url

    # Set the list of app names to show in the web UI.
    def apps=(value)
      @apps = Array(value).collect(&:to_s)
    end

    def apps
      @apps ||= ENV.fetch("SPARTAN_APM_APPS", "").split(/\s*,\s*/)
    end

    # Set a list of errors to ignore. If an error matches a designated class,
    # then it will not be recorded as an error. You can use this to strip out
    # expected errors so they don't show up in the error monitoring.
    # @param error_classes [Class, Module, String] class, class name, or module to ignore
    def ignore_errors(error_classes)
      error_classes = Array(error_classes)
      @ignore_error_modules = error_classes.select { |klass| klass.is_a?(Module) }
      @ignore_error_class_names = Set.new(error_classes.reject { |klass| klass.is_a?(Module) })
    end

    # @return [Boolean] Returns true if the error matches an error class specified with ignore_errors.
    def ignore_error?(error)
      return false unless defined?(@ignore_error_class_names) && @ignore_error_class_names
      return true if @ignore_error_modules.any? { |klass| error.is_a?(klass) }
      return false if @ignore_error_class_names.empty?
      ignore_error = false
      klass = error.class
      while klass && klass.superclass != klass
        if @ignore_error_class_names.include?(klass.name)
          ignore_error = true
          break
        end
        klass = klass.superclass
      end
      ignore_error
    end

    # A backtrace cleaner can be set with a Proc (or anything that responds to `call`) to
    # remove extraneous lines from error backtraces. Setting up a backtrace cleaner
    # can save space in redis and make the traces easier to follow by removing uninteresting
    # lines. The Proc will take a backtrace as an array and should return an array.
    attr_writer :backtrace_cleaner

    # Clean an error backtrace by passing it to the backtrace cleaner if one was set.
    def clean_backtrace(backtrace)
      if defined?(@backtrace_cleaner) && @backtrace_cleaner && backtrace
        cleaned = Array(@backtrace_cleaner.call(backtrace[1, backtrace.size]))
        # Alway make sure the top line of the trace is included.
        cleaned.unshift(backtrace[0])
        cleaned
      else
        backtrace
      end
    end

    # The measure block should be wrapped around whatever you want to consider a request
    # in your application (i.e. web request, asynchronous job execution, etc.). This method
    # will collect all instrumentation stats that occur within the block and report them
    # as a single unit.
    #
    # In order to measure both an app name and an action name need to be provided. The app
    # name should be something that describes the application function (i.e. "web" for web
    # requests) while the action should describe the particular action being taken by the
    # request (i.e. controller and action for a web request, worker name for an asynchronous
    # job, etc.).
    #
    # The action name is optional here, but it is required in order for metrics to
    # be recorded. This is because a measure block should encompass as much of the request
    # as possible in order to be accurate. However, this might be before the action name
    # is known. The action can be provided retroactively from within the block by setting
    # `SpartanAPM.current_action`.
    #
    # @param app [String, Symbol] The name of the app that is collecting metrics.
    # @param action [String, Symbol] The name of the action that is being performed.
    def measure(app, action = nil)
      if Thread.current[:spartan_apm_measure].nil? && (sample_rate >= 1.0 || rand < sample_rate)
        measure = Measure.new(app, action)
        Thread.current[:spartan_apm_measure] = measure
        # rubocop:disable Lint/RescueException
        begin
          yield
        rescue Exception => e
          measure.capture_error(e) unless ignore_error?(e)
          raise
        ensure
          Thread.current[:spartan_apm_measure] = nil
          measure.record!
        end
        # rubocop:enable Lint/RescueException
      else
        yield
      end
    end

    # Set the action name for the current measure. This allows you to set up a measure
    # before you know the action name and then provide it later once that information
    # is available.
    # @param action [String, Symbol]
    def current_action=(action)
      measure = Thread.current[:spartan_apm_measure]
      measure.action = action if measure
    end

    # Set the app name for the current measure. This allows you to set up a measure
    # and override the app name if you want to segment some of your requests into a
    # different app.
    # @param app [String, Symbol]
    def current_app=(app)
      measure = Thread.current[:spartan_apm_measure]
      measure.app = app if measure
    end

    # Capture a metric for a block. The metric value recorded will be the amount of time
    # in seconds elapsed during block execution and will be stored with the current
    # measure.
    #
    # The exclusive flag can be set to true to indicate that no other components should
    # be captured in the block. This can be used if you want to measure one component
    # as a unit but that component calls other instrumented components. For example, if you
    # are instrumenting HTTP requests, but also want to instrument a service call that makes
    # an HTTP request, you would capture the service call as exclusive.
    #
    # @param name [String, Symbol] The name of the component being measured.
    # @param exclusive [Boolean]
    def capture(name, exclusive: false)
      measure = Thread.current[:spartan_apm_measure]
      if measure
        measure.capture(name, exclusive: exclusive) { yield }
      else
        yield
      end
    end

    # Capture a time for a component in the current measure. This is the same as calling
    # `capture` but without a block and passing the value explicitly.
    def capture_time(name, elapsed_time)
      measure = Thread.current[:spartan_apm_measure]
      measure&.capture_time(name, elapsed_time)
    end

    # Capture an error in the current measure.
    def capture_error(error)
      measure = Thread.current[:spartan_apm_measure]
      if measure && !ignore_error?(error)
        measure.capture_error(error)
      end
    end

    # Set the host name for the current process. Defaults to the system host name.
    attr_writer :host

    # @return The host name.
    def host
      @host ||= Socket.gethostname
    end

    # Set the Redis instance to use for storing metrics. This can be either a Redis
    # instance or a Proc that returns a Redis instance. If it is a Proc, the Proc
    # will be be called at runtime.
    #
    # If the Redis instance is not explicitly set, then the default connection URL
    # will be looked up from environment variables. If the value of `SPARTAN_APM_REDIS_URL_PROVIDER`
    # is set, then the URL will be gotten from the named environment variable. Otherwise
    # it will use the value in `REDIS_URL`.
    attr_writer :redis

    # @return [Redis] Redis instance where metrics are stored.
    def redis
      @redis ||= default_redis
      @redis.is_a?(Proc) ? @redis.call : @redis
    end

    # Set a list of patterns to ignore for an app. Patterns can be passed in as either
    # a string to match or a Regexp. Strings can be specified with wildcards using "*"
    # (i.e. "/debug/*" would match "/debug/info", etc.).
    # @param app [String, Symbol] The app name the patterns are for.
    # @param patterns [String, Regexp] Patterns to match that should be ignored.
    def ignore_requests(app, *patterns)
      app = app.to_s
      patterns = patterns.compact
      if patterns.empty?
        @ignore_patterns.delete(app)
      else
        regexp_patterns = patterns.flatten.collect do |pattern|
          if pattern.is_a?(Regexp)
            pattern
          else
            exp = Regexp.escape(pattern).gsub("\\*", "(?:.*)")
            Regexp.new("\\A#{exp}\\z")
          end
        end
        @ignore_patterns[app] = Regexp.union(regexp_patterns)
      end
    end

    # Determine if a value is set to be ignored. This method should be called
    # by whatever code is calling `measure`. There is no set definition for what the
    # value being passed should be and it left up to the implementation to set
    # a convention.
    #
    # For instance in the bundled Rack implementation, the value passed to this
    # method is the web request path. This allows that implementation to disable
    # instrumentation for a set of request paths.
    def ignore_request?(app, value)
      return false if value.nil?
      !!@ignore_patterns[app.to_s]&.match(value.to_s)
    end

    # The web UI will use a locked version of the plotly.js library from the official
    # distribution CDN. If your company security policy requires all tools to pull
    # from an internal source, you can change the URL with this setting.
    attr_accessor :plotly_js_url

    # @api private
    # Get the bucket for the specified time.
    # @return [Integer]
    def bucket(time)
      (time.to_f / 60.0).floor
    end

    # @api private
    # Get the time for the specified bucket.
    # @return [Time]
    def bucket_time(bucket)
      Time.at(bucket * 60.0)
    end

    # @api private
    # Used for testing for disabling asynchronous metric persistence.
    def persist_asynchronously?
      unless defined?(@persist_asynchronously)
        @persist_asynchronously = true
      end
      @persist_asynchronously
    end

    # @api private
    # Used for testing for disabling asynchronous metric persistence.
    def persist_asynchronously=(value)
      @persist_asynchronously = !!value
    end

    private

    def default_redis
      var_name = ENV.fetch("SPARTAN_APM_REDIS_URL_PROVIDER", "REDIS_URL")
      url = ENV[var_name]
      Redis.new(url: url)
    end
  end
end

require_relative "spartan_apm/string_cache"
require_relative "spartan_apm/error_info"
require_relative "spartan_apm/measure"
require_relative "spartan_apm/persistence"
require_relative "spartan_apm/report"
require_relative "spartan_apm/metric"
require_relative "spartan_apm/instrumentation"
require_relative "spartan_apm/middleware"
require_relative "spartan_apm/web"

if defined?(Rails::Engine)
  require_relative "spartan_apm/engine"
end

at_exit do
  SpartanAPM::Measure.flush
end
