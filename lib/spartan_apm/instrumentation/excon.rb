# frozen_string_literal: true

module SpartanAPM
  module Instrumentation
    class Excon < Base
      def initialize
        @klass = ::Excon::Connection if defined?(::Excon::Connection)
        @name = :http
        @methods = [:request]
      end
    end
  end
end
