# frozen_string_literal: true

module SpartanAPM
  module Instrumentation
    class EthonMulti < Base
      def initialize
        @klass = ::Ethon::Multi if defined?(::Ethon::Multi)
        @name = :http
        @methods = [:perform]
      end
    end
  end
end
