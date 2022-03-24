# frozen_string_literal: true

module SpartanAPM
  # Data structure for information about the request metrics for a particular time.
  class Metric
    attr_reader :time
    attr_accessor :count, :avg, :p50, :p90, :p99, :error_count, :components

    def initialize(time)
      @time = time
      @components = {}
    end

    def component_names
      @components.keys.collect { |n| n.to_s.freeze }
    end

    def component_request_time(name)
      Array(@components[name.to_s])[0]
    end

    def component_request_count(name)
      Array(@components[name.to_s])[1]
    end
  end
end
