# frozen_string_literal: true

module SpartanAPM
  module Middleware
  end
end

require_relative "middleware/rack"
require_relative "middleware/sidekiq"
