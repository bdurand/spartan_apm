# frozen_string_literal: true

module SpartanAPM
  module Instrumentation
    class Elasticsearch < Base
      def initialize
        if defined?(::Elastic::Transport::Client)
          @klass = ::Elastic::Transport::Client
        elsif defined?(::Elasticsearch::Transport::Client)
          @klass = ::Elasticsearch::Transport::Client
        end
        @name = :elasticsearch
        @methods = [:perform_request]
        @exclusive = true
      end
    end
  end
end
