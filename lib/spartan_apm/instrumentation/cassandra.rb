# frozen_string_literal: true

module SpartanAPM
  module Instrumentation
    class Cassandra < Base
      def initialize
        @klass = ::Cassandra::Session if defined?(::Cassandra::Session)
        @name = :cassandra
        @methods = [:execute, :prepare]
      end
    end
  end
end
