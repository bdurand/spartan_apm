# frozen_string_literal: true

module SpartanAPM
  module Instrumentation
    class TyphoeusMulti < Base
      def initialize
        @klass = ::Typhoeus::Hydra if defined?(::Typhoeus::Hydra)
        @name = :http
        @methods = [:run]
      end
    end
  end
end
