# frozen_string_literal: true

module SpartanAPM
  module Instrumentation
    class Redis < Base
      def initialize
        @klass = ::Redis::Client if defined?(::Redis::Client)
        @name = :redis
        @methods = [:process]
      end
    end
  end
end
