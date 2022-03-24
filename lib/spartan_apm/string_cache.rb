# frozen_string_literal: true

module SpartanAPM
  # Simple string cache. This is used to prevent memory bloat
  # when collecting measures by caching and reusing strings
  # in the enqueued metrics rather than having the same string
  # repeated for each request.
  class StringCache
    def initialize
      @cache = Concurrent::Hash.new
    end

    # Fetch a string from the cache. If it isn't already there,
    # then it will be frozen and stored in the cache so the same
    # object can be returned by subsequent calls for a matching string.
    def fetch(value)
      return nil if value.nil?
      value = value.to_s
      cached = @cache[value]
      unless cached
        cached = -value
        @cache[cached] = cached
      end
      cached
    end
  end
end
