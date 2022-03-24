# frozen_string_literal: true

require "rack"

require_relative "lib/spartan_apm"

if SpartanAPM.apps.empty?
  raise ArgumentError.new("Apps must be specified in comma delimited list in the SPARTAN_APM environment variable")
else
  puts "Using apps #{SpartanAPM.apps.join(', ')} in environments #{SpartanAPM.environments.join(', ')}"
end

# Make sure we don't log access tokens.
class SecureLogger
  ACCESS_TOKEN_PATTERN = /([?&]access_token=)[^&\s]+/

  def write(message)
    $stdout.write(message.gsub(ACCESS_TOKEN_PATTERN, '\1******'))
  end
end

use Rack::CommonLogger, SecureLogger.new

basic_auth_user = ENV.fetch("BASIC_AUTH_USER", "")
basic_auth_password = ENV.fetch("BASIC_AUTH_PASSWORD", "")
unless basic_auth_user.empty?
  use Rack::Auth::Basic do |user, password|
    user == basic_auth_user && password.to_s == basic_auth_password
  end
end

if File.exist?(File.join(__dir__, "public", "plotly.js"))
  use Rack::Static, urls: ["/plotly.js"], root: "public"
end

run SpartanAPM::Web::Router.new
