# frozen_string_literal: true

module SpartanAPM
  module Middleware
    module Rack
      class << self
        # Get the app name associated with web requests. Defaults to "web".
        # @return [String]
        def app_name
          @app_name ||= "web"
        end

        # Set the app name associated with web requests.
        # @param value [String, Symbol]
        def app_name=(value)
          @app_name = value&.to_s
        end
      end
    end
  end
end

require_relative "rack/end_middleware"
require_relative "rack/start_middleware"
