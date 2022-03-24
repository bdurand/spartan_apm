# frozen_string_literal: true

module SpartanAPM
  module Instrumentation
    class HTTPClient < Base
      def initialize
        @klass = ::HTTPClient if defined?(::HTTPClient)
        @name = :http
        @methods = [:do_get_block]
      end
    end
  end
end
