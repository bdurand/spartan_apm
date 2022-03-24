# frozen_string_literal: true

module SpartanAPM
  # Data structure for capturing information about errors.
  class ErrorInfo
    attr_reader :time, :class_name, :message, :backtrace
    attr_accessor :count

    def initialize(time, class_name, message, backtrace, count)
      @time = time
      @class_name = class_name
      @message = message
      @backtrace = backtrace
      @count = count.to_i
    end
  end
end
