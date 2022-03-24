# frozen_string_literal: true

module SpartanAPM
  module Instrumentation
    # Base class for describing how to inject instrumentation code into another class.
    # This class should be extended and the subclass should set the klass, name, and methods
    # attributes in the constructor.
    class Base
      # The class that should be instrumented.
      attr_accessor :klass

      # The component name that metrics should be recorded as.
      attr_accessor :name

      # Flag indicating if metrics should be captured exclusively.
      attr_accessor :exclusive

      # List of instance methods to instrument.
      attr_accessor :methods

      # Inject instrumentation code into the specified class' methods.
      def instrument!
        raise ArgumentError.new("klass not specified") unless klass
        raise ArgumentError.new("name not specified") unless name
        Instrumentation.instrument!(klass, name, methods, exclusive: exclusive, module_name: "#{self.class.name.split("::").last}Instrumentation")
      end

      # Determine if the instrumentation definition is valid.
      def valid?
        return false if klass.nil? || name.nil?
        all_methods = klass.public_instance_methods + klass.protected_instance_methods + klass.private_instance_methods
        Array(methods).all? { |m| all_methods.include?(m) }
      end
    end
  end
end
