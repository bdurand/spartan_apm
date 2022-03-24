# frozen_string_literal: true

module SpartanAPM
  module Middleware
    module Rack
      # Middleware that should be added to the start of the start of the middleware chain.
      class StartMiddleware
        def initialize(app)
          @app = app
        end

        def call(env)
          if SpartanAPM.ignore_request?("web", env["PATH_INFO"])
            @app.call(env)
          else
            start_time = Time.now.to_f

            # This value is used in EndMiddleware to capture how long all the middleware
            # between the two middlewares took to execute.
            env["spartan_apm.middleware_start_time"] = start_time

            SpartanAPM.measure("web") do
              begin
                @app.call(env)
              ensure
                # Record how long the web request was enqueued before the Rack server
                # got the request if that information is available.
                enqueued_at_time = request_queue_start_time(env)
                if enqueued_at_time && start_time > enqueued_at_time
                  SpartanAPM.capture_time(:queue, start_time - enqueued_at_time)
                end
              end
            end
          end
        end

        private

        def request_queue_start_time(env)
          # There's a few of differing conventions on where web servers record the
          # start time on a request in the proxied HTTP headers.
          header = (env["HTTP_X_REQUEST_START"] || env["HTTP_X_QUEUE_START"])
          start_time = nil
          if header
            header = header[2, header.size] if header.start_with?("t=")
            t = header.to_f
            # Header could be in seconds, milliseconds, or microseconds
            t /= 1000.0 if t > 5_000_000_000
            t /= 1000.0 if t > 5_000_000_000
            start_time = t if t > 0
          end
          start_time
        end
      end
    end
  end
end
