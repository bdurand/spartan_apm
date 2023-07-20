# frozen_string_literal: true

module SpartanAPM
  # This class holds the metrics captured during a request. Metrics are captured
  # in one minute increments and then written to Redis.
  class Measure
    attr_reader :app, :action, :timers, :counts, :error, :error_message, :error_backtrace

    @mutex = Mutex.new
    @current_measures = nil
    @last_bucket = nil
    @string_cache = StringCache.new
    @error_cache = Concurrent::Map.new

    class << self
      # Get the list of Measures stored for the current minute time bucket. Every minute
      # this list is started anew. This method will also automatically kick off the process
      # to persist Measures from the previous time bucket to Redis if necessary.
      # @return [Concurrent::Array<Measure>]
      def current_measures
        bucket = SpartanAPM.bucket(Time.now)
        last_bucket = @last_bucket
        if bucket != last_bucket
          persist_measures = nil
          @mutex.synchronize do
            # This check is made again within the mutex block so that we don't have
            # to lock the mutex every time we make the check if the bucket has changed.
            if bucket != @last_bucket
              persist_measures = @current_measures
              @last_bucket = bucket
              @current_measures = Concurrent::Array.new
              @string_cache = StringCache.new
              @error_cache = {}
            end
          end

          if persist_measures && !persist_measures.empty?
            store_measures(last_bucket, persist_measures)
          end
        end

        @current_measures
      end

      # @api private
      # Used for consistency in test cases.
      def clear_current_measures!
        @mutex.synchronize do
          @current_measures = nil
          @last_bucket = nil
        end
      end

      # Flush all currently enqueued Measures to Redis.
      def flush
        return if @last_bucket.nil?
        bucket = nil
        measures = nil
        @mutex.synchronize do
          bucket = @last_bucket
          measures = @current_measures
          @current_measures = Concurrent::Array.new
          @string_cache = StringCache.new
          @error_cache = {}
        end
        unless measures.empty?
          Persistence.store!(bucket, measures)
        end
      end

      # @api private
      #
      # Fetch error information from a cache. The cache is used since backtraces
      # can be quite long and, if the application got into a bad state, a lot of
      # errors could be generated in a short time. The cache is here to prevent
      # memory bloat if that happens by only storing one copy of each error trace.
      #
      # There is also a hard limit of 1000 distinct errors at a time. This is a
      # protection in case errors end up with dynamically generated traces so that
      # don't use up all the memory. If your application gets over 1000 distinct
      # errors in a minute, seeing a truncated list of them is the least of your
      # worries.
      def error_cache_fetch(error)
        return nil unless error
        backtrace = SpartanAPM.clean_backtrace(error.backtrace)
        error_key = Digest::MD5.hexdigest("#{error.class.name} #{backtrace&.join}")
        cached_error = @error_cache[error_key]
        unless cached_error
          return nil if @error_cache.size > 1000
          cached_error = [error.class.name, error.message, backtrace]
          @error_cache[error_key] = cached_error
        end
        cached_error
      end

      attr_reader :string_cache

      private

      def store_measures(last_bucket, measures)
        if SpartanAPM.persist_asynchronously?
          Thread.new do
            Persistence.store!(last_bucket, measures)
          rescue => e
            log_storage_error(e)
          end
        else
          begin
            Persistence.store!(last_bucket, measures)
          rescue => e
            log_storage_error(e)
          end
        end
      end

      def log_storage_error(error)
        message = "SpartanAPM error storing measures: #{error.inspect}\n#{error.backtrace.join("\n")}"
        if SpartanAPM.logger
          SpartanAPM.logger.error(message)
        else
          warn message
        end
      end
    end

    def initialize(app, action = nil)
      @app = self.class.string_cache.fetch(app)
      @action = self.class.string_cache.fetch(action) if action
      @timers = Hash.new(0.0)
      @counts = Hash.new(0)
      @current_name = nil
      @current_start_time = nil
      @current_exclusive = false
    end

    def action=(value)
      @action = self.class.string_cache.fetch(value)
    end

    def app=(value)
      @app = self.class.string_cache.fetch(value)
    end

    # Capture the timing for a component. See SpartanAPM.capture for more info.
    def capture(name, exclusive: false)
      name = name.to_sym
      if @current_exclusive
        # Already capturing from within an exclusive block, so don't interrupt that capture.
        yield
      else
        start_time = SpartanAPM.clock_time
        restore_name = @current_name
        if restore_name
          @timers[restore_name] += start_time - @current_start_time
        end
        @current_name = name
        @current_start_time = start_time
        @current_exclusive = exclusive
        begin
          yield
        ensure
          end_time = SpartanAPM.clock_time
          @timers[name] += end_time - @current_start_time
          @counts[name] += 1
          if restore_name
            @current_name = restore_name
            @current_start_time = end_time
          else
            @current_name = nil
            @current_start_time = nil
          end
        end
      end
    end

    # Capture the timing for a component. See SpartanAPM#capture_time for more info.
    def capture_time(name, elapsed_time)
      name = name.to_sym
      @timers[name] += elapsed_time.to_f
      @counts[name] += 1
    end

    # Capture an error. See SpartanAPM#capture_error for more info.
    def capture_error(error)
      @error, @error_message, @error_backtrace = self.class.error_cache_fetch(error)
    end

    # This method must be called to add the Measure to the measures for
    # the current bucket.
    def record!
      if (action && !@timers.empty?) || error
        self.class.current_measures << self
      end
    end
  end
end
