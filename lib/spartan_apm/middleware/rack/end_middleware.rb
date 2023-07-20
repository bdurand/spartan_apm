# frozen_string_literal: true

module SpartanAPM
  module Middleware
    module Rack
      # Middleware that should be added of the end of the middleware chain.
      class EndMiddleware
        def initialize(app)
          @app = app
        end

        def call(env)
          start_time = SpartanAPM.clock_time
          SpartanAPM.capture(:app) do
            begin
              @app.call(env)
            ensure
              # Capture how much time was spent in middleware.
              middleware_start_time = env["spartan_apm.middleware_start_time"]
              if middleware_start_time
                SpartanAPM.capture_time(:middleware, start_time.to_f - middleware_start_time)
              end
            end
          end
        end
      end
    end
  end
end
