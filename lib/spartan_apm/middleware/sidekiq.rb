# frozen_string_literal: true

module SpartanAPM
  module Middleware
    module Sidekiq
      class << self
        # Get the app name associated with Sidekiq requests. Defaults to "sidekiq".
        # @return [String]
        def app_name
          @app_name ||= "sidekiq"
        end

        # Set the app name associated with Sidekiq requests.
        # @param value [String, Symbol]
        def app_name=(value)
          @app_name = value&.to_s
        end
      end
    end
  end
end

require_relative "sidekiq/end_middleware"
require_relative "sidekiq/start_middleware"
