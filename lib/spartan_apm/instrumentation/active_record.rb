# frozen_string_literal: true

module SpartanAPM
  module Instrumentation
    class ActiveRecord < Base
      def initialize
        @klass = ::ActiveRecord::Base.connection.class if defined?(::ActiveRecord::Base)
        @name = :database
        @methods = [:exec_query]
      end
    end
  end
end
