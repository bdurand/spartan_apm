# frozen_string_literal: true

module SpartanAPM
  module Middleware
    module Sidekiq
      # Middleware that should be added to the start of the start of the middleware chain.
      class StartMiddleware
        def call(worker, msg, queue, &block)
          if SpartanAPM.ignore_request?(Sidekiq.app_name, worker.class.name)
            yield
          else
            start_time = Time.now.to_f

            # This value is used in EndMiddleware to capture how long all the middleware
            # between the two middlewares took to execute.
            msg["spartan_apm.middleware_start_time"] = start_time

            SpartanAPM.measure(Sidekiq.app_name, worker.class.name) do
              begin
                yield
              ensure
                # Capture how long the message was enqueued in Redis before a worker got the job.
                enqueued_time = msg["enqueued_at"].to_f if msg.is_a?(Hash)
                if enqueued_time && enqueued_time > 0 && start_time > enqueued_time
                  SpartanAPM.capture_time(:queue, start_time - enqueued_time)
                end
              end
            end
          end
        end
      end
    end
  end
end
