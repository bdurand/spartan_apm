# frozen_string_literal: true

module SpartanAPM
  module Instrumentation
    class Curb < Base
      def initialize
        @klass = ::Curl::Easy if defined?(::Curl::Easy)
        @name = :http
        @methods = [:http]
      end
    end
  end
end
