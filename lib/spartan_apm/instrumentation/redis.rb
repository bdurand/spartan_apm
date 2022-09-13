# frozen_string_literal: true

module SpartanAPM
  module Instrumentation
    class Redis < Base
      def initialize
        @name = :redis
        if defined?(::RedisClient::ConnectionMixin)
          @klass = ::RedisClient::ConnectionMixin
          @methods = [:call]
        elsif defined?(::Redis::Client)
          @klass = ::Redis::Client
          @methods = [:process]
        end
      end
    end
  end
end
