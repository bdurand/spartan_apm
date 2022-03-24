# frozen_string_literal: true

module SpartanAPM
  module Web
    # Helper classes for the web UI.
    class Helpers
      VIEWS_DIR = File.expand_path(File.join("..", "..", "..", "app", "views"), __dir__).freeze

      @mutex = Mutex.new
      @templates = {}

      class << self
        # @api private
        # ERB template cache.
        def template(path)
          template = @templates[path]
          unless template
            template = File.read(path)
            if path.end_with?(".erb")
              template = ERB.new(File.read(path))
            end
            @mutex.synchronize { @templates[path] = template } unless ENV["DEVELOPMENT"] == "true"
          end
          template
        end
      end

      attr_reader :request

      def initialize(request)
        @request = request
      end

      # Render an ERB template.
      # @param path [String] Relative path to the template in the gem app/views directory.
      # @variables [Hash] Local variables to set for the ERB binding.
      def render(path, variables = {})
        file_path = File.expand_path(File.join(VIEWS_DIR, *path.split("/")))
        raise ArgumentError.new("Invalid template ") unless file_path.start_with?(VIEWS_DIR)
        template = self.class.template(file_path)
        if template.is_a?(ERB)
          template.result(get_binding(variables))
        else
          template
        end
      end

      # HTML escape text.
      def h(text)
        ERB::Util.h(text.to_s)
      end

      # List of available apps.
      def apps
        SpartanAPM.apps
      end

      # List of available apps.
      def environments
        SpartanAPM.environments
      end

      # Optional URL for authenticating access to the web UI.
      def authentication_url
        SpartanAPM.authentication_url
      end

      # Optional application name to show in the web UI.
      def application_name
        SpartanAPM.application_name || "SpartanAPM"
      end

      # Optional link URL back to the application for the web UI.
      def application_url
        SpartanAPM.application_url
      end

      private

      def get_binding(local_variables = {})
        local_variables.each do |name, value|
          binding.local_variable_set(name, value)
        end
        binding
      end
    end
  end
end
