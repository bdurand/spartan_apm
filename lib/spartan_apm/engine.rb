# frozen_string_literal: true

module SpartanAPM
  # Rails engine that will automatically instrument a Rails application
  # for web requests. If Sidekiq is installed, it will be instrumented
  # as well.
  class Engine < Rails::Engine
    initializer "spartan_apm" do |app|
      ActiveSupport.on_load(:action_controller) do
        ActionController::Base.prepend_around_action do |controller, action|
          # rubocop:disable Lint/RescueException
          begin
            action.call
          rescue Exception => e
            SpartanAPM.capture_error(e)
            raise
          end
          # rubocop:enable Lint/RescueException
        end

        if defined?(Sidekiq) && Sidekiq.server?
          Sidekiq.configure_server do |config|
            config.server_middleware do |chain|
              chain.prepend SpartanAPM::Middleware::Sidekiq::StartMiddleware
              chain.add SpartanAPM::Middleware::Sidekiq::EndMiddleware
            end
          end
        end

        app.config.middleware.insert(0, SpartanAPM::Middleware::Rack::StartMiddleware)
        app.config.middleware.use(SpartanAPM::Middleware::Rack::EndMiddleware)
      end
    end

    config.after_initialize do
      SpartanAPM.configure do |config|
        config.env = Rails.env.to_s unless config.env_set?
        config.logger ||= Rails.logger
        apps = ["web"]
        apps << "sidekiq" if defined?(Sidekiq)
        config.apps = apps if config.apps.empty?
      end
    end
  end
end
