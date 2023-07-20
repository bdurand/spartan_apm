# frozen_string_literal: true

module SpartanAPM
  module Instrumentation
    class Patron < Base
      def initialize
        @klass = ::Patron::Session if defined?(::Patron::Session)
        @name = :http
        @methods = [:request]
      end
    end
  end
end
