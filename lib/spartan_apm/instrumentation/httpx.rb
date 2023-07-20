# frozen_string_literal: true

module SpartanAPM
  module Instrumentation
    class HTTPX < Base
      def initialize
        @klass = ::HTTPX::Session if defined?(::HTTPX::Session)
        @name = :http
        @methods = [:send_requests]
      end
    end
  end
end
