# frozen_string_literal: true

module SpartanAPM
  module Instrumentation
    class EthonEasy < Base
      def initialize
        @klass = ::Ethon::Easy if defined?(::Ethon::Easy)
        @name = :http
        @methods = [:perform]
      end
    end
  end
end
