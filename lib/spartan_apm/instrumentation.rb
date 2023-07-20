# frozen_string_literal: true

module SpartanAPM
  # Code for instrumenting other classes with capture blocks to capture how long
  # calling specified methods take.
  module Instrumentation
    class << self
      # Apply all the bundled instrumenters.
      def auto_instrument!
        ActiveRecord.new.tap { |instance| instance.instrument! if instance.valid? }
        Bunny.new.tap { |instance| instance.instrument! if instance.valid? }
        Cassandra.new.tap { |instance| instance.instrument! if instance.valid? }
        Curb.new.tap { |instance| instance.instrument! if instance.valid? }
        Dalli.new.tap { |instance| instance.instrument! if instance.valid? }
        Elasticsearch.new.tap { |instance| instance.instrument! if instance.valid? }
        EthonEasy.new.tap { |instance| instance.instrument! if instance.valid? }
        EthonMulti.new.tap { |instance| instance.instrument! if instance.valid? }
        Excon.new.tap { |instance| instance.instrument! if instance.valid? }
        HTTPClient.new.tap { |instance| instance.instrument! if instance.valid? }
        HTTP.new.tap { |instance| instance.instrument! if instance.valid? }
        HTTPX.new.tap { |instance| instance.instrument! if instance.valid? }
        NetHTTP.new.tap { |instance| instance.instrument! if instance.valid? }
        Patron.new.tap { |instance| instance.instrument! if instance.valid? }
        Redis.new.tap { |instance| instance.instrument! if instance.valid? }
        TyphoeusEasy.new.tap { |instance| instance.instrument! if instance.valid? }
        TyphoeusMulti.new.tap { |instance| instance.instrument! if instance.valid? }
      end

      # Instrument a class by surrounding specified instance methods with capture blocks.
      def instrument!(klass, name, methods, exclusive: false, module_name: nil)
        # Create a module that will be prepended to the specified class.
        unless module_name
          camelized_name = name.to_s.gsub(/[^a-z0-9]+([a-z0-9])/i) { |m| m[m.length - 1, m.length].upcase }
          camelized_name = "#{camelized_name[0].upcase}#{camelized_name[1, camelized_name.length]}"
          module_name = "#{klass.name.split("::").join}#{camelized_name}Instrumentation"
        end
        if const_defined?(module_name)
          raise ArgumentError.new("#{name} has alrady been instrumented in #{klass.name}")
        end

        # The method of overriding kwargs changed in ruby 2.7
        ruby_major, ruby_minor, _ = RUBY_VERSION.split(".").collect(&:to_i)
        ruby_3_args = (ruby_major >= 3 || (ruby_major == 2 && ruby_minor >= 7))
        splat_args = (ruby_3_args ? "..." : "*args, &block")

        # Dark arts & witchery to dynamically generate the module methods.
        instrumentation_module = const_set(module_name, Module.new)
        Array(methods).each do |method_name|
          instrumentation_module.class_eval <<~RUBY, __FILE__, __LINE__ + 1
            def #{method_name}(#{splat_args})
              SpartanAPM.capture(#{name.to_sym.inspect}, exclusive: #{exclusive.inspect}) do
                super(#{splat_args})
              end
            end
          RUBY
        end

        klass.prepend(instrumentation_module)
      end
    end
  end
end

require_relative "instrumentation/base"
require_relative "instrumentation/active_record"
require_relative "instrumentation/bunny"
require_relative "instrumentation/cassandra"
require_relative "instrumentation/curb"
require_relative "instrumentation/dalli"
require_relative "instrumentation/elasticsearch"
require_relative "instrumentation/ethon_easy"
require_relative "instrumentation/ethon_multi"
require_relative "instrumentation/excon"
require_relative "instrumentation/httpclient"
require_relative "instrumentation/http"
require_relative "instrumentation/httpx"
require_relative "instrumentation/net_http"
require_relative "instrumentation/patron"
require_relative "instrumentation/redis"
require_relative "instrumentation/typhoeus_easy"
require_relative "instrumentation/typhoeus_multi"
