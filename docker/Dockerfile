FROM ruby:alpine

RUN apk --no-cache add build-base

WORKDIR /spartan_apm

COPY docker/Gemfile ./Gemfile

RUN bundle config set --local no-cache "true" && \
    bundle config set --local path .bundle && \
    bundle install --jobs 4 --retry 2 && \
    rm -rf .bundle/cache/* && \
    find .bundle/ruby/*/gems/ -name "*.c" -delete && \
    find .bundle/ruby/*/gems/ -name "*.o" -delete && \
    rm -rf .bundle/ruby/*/gems/test && \
    rm -rf .bundle/ruby/*/gems/spec

COPY . ./

RUN bundle exec rake download_plotly_js

ENV PORT 80
EXPOSE $PORT

ENV MALLOC_ARENA_MAX 2
ENV RUBY_GC_HEAP_GROWTH_FACTOR 1.1

ENV SPARTAN_APM_PLOTLY_JS_URL /plotly.js

CMD bundle exec puma -C docker/puma.rb
