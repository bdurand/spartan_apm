# frozen_string_literal: true

module SpartanAPM
  module Middleware
    module Sidekiq
      # Middleware that should be added of the end of the middleware chain.
      class EndMiddleware
        def call(worker, msg, queue, &block)
          start_time = SpartanAPM.clock_time
          SpartanAPM.capture(:app) do
            begin
              yield
            ensure
              # Capture how much time was spent in middleware.
              middleware_start_time = msg["spartan_apm.middleware_start_time"]
              if middleware_start_time
                SpartanAPM.capture_time(:middleware, start_time - middleware_start_time)
              end
            end
          end
        end
      end
    end
  end
end
