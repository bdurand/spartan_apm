# frozen_string_literal: true

module SpartanAPM
  module Instrumentation
    class NetHTTP < Base
      def initialize
        @klass = ::Net::HTTP if defined?(::Net::HTTP)
        @name = :http
        @methods = [:request]
      end
    end
  end
end
