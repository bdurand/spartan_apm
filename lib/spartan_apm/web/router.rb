# frozen_string_literal: true

require "erb"

module SpartanAPM
  module Web
    # Rack application for serving up the web UI. The application can either
    # be mounted as a Rack application or as Rack middleware.
    class Router
      ASSET_ROOT_DIR = File.expand_path(File.join(__dir__, "..", "..", "..", "app", "assets"))

      def initialize(root_path = "")
        @root_path = root_path.chomp("/")
        @root_prefix = "#{@root_path}/"
      end

      def call(env)
        path = env["PATH_INFO"]
        response = nil
        if path.start_with?(@root_path)
          app_path = path[@root_path.length, path.length]
          request = Rack::Request.new(env)
          case app_path
          when ""
            response = [302, {"location" => root_url(request)}, []]
          when "/"
            body = Helpers.new(request).render("index.html.erb")
            response = [200, {"content-type" => "text/html; charset=utf-8", "cache-control" => "no-cache"}, [body]]
          when "/metrics"
            response = json_response(ApiRequest.new(request).metrics)
          when "/live_metrics"
            response = json_response(ApiRequest.new(request).live_metrics)
          when "/errors"
            response = json_response(ApiRequest.new(request).errors)
          when "/actions"
            response = json_response(ApiRequest.new(request).actions)
          when "/hosts"
            response = json_response(ApiRequest.new(request).hosts)
          else
            if app_path.start_with?("/assets/")
              response = asset_response(app_path.sub("/assets/", ""))
            end
          end
        end

        response || not_found_response
      end

      private

      def not_found_response
        [404, {"content-type" => "text/plain"}, ["Not found"]]
      end

      def json_response(result)
        [200, {"content-type" => "application/json; charset=utf-8", "cache-control" => "no-cache"}, [JSON.dump(result)]]
      end

      def asset_response(asset_path)
        file_path = File.expand_path(File.join(ASSET_ROOT_DIR, asset_path.split("/")))
        return nil unless file_path.start_with?(ASSET_ROOT_DIR) && File.exist?(file_path)
        data = File.read(file_path)
        headers = {"content-type" => mime_type(file_path)}
        headers["cache-control"] = "max-age=604800" if asset_path.match?(/\d\./)
        [200, headers, [data]]
      end

      def mime_type(file_path)
        extension = file_path.split(".").last
        case extension
        when "css"
          "text/css"
        when "js"
          "application/javascript"
        when "svg"
          "image/svg+xml; charset=utf-8"
        when "png"
          "image/png"
        else
          "application/octet-stream"
        end
      end

      def root_url(request)
        request.url.sub(/$|(\?.*)/, '/\1')
      end
    end
  end
end
