# frozen_string_literal: true

module SpartanAPM
  module Instrumentation
    class TyphoeusEasy < Base
      def initialize
        @klass = ::Typhoeus::Request if defined?(::Typhoeus::Request)
        @name = :http
        @methods = [:run]
      end
    end
  end
end
