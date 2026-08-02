# frozen_string_literal: true

module Coatepec
  module Introspection
    # Filters an ActiveRecord validator's `options` hash down to genuinely
    # primitive values before it's serialized as rails_model output.
    # Validator options can carry arbitrary Ruby objects (Proc for `if:`/
    # `unless:`, Regexp for `with:`, etc.) that must never be JSON-serialized
    # as-is -- Proc#to_s leaks the target app's absolute source file path
    # and line number. Only genuinely primitive values pass through;
    # anything else is silently dropped.
    module SafeOptions
      module_function

      def call(options)
        options.filter_map do |key, value|
          safe_value = value_for(value)
          [key.to_s, safe_value] unless safe_value.nil? && !value.nil?
        end.to_h
      end

      def value_for(value)
        case value
        when String, Numeric, TrueClass, FalseClass, NilClass
          value
        when Symbol
          value.to_s
        when Array
          array_value_for(value)
        end
      end

      # Symbol *elements* are stringified exactly as a bare Symbol value is
      # above: `inclusion: { in: %i[draft published] }` is one of the most
      # common option shapes in Rails, and dropping the whole `in:` key for it
      # while keeping the single-Symbol equivalent would be arbitrary. An
      # array still holding anything non-primitive after that is dropped
      # whole -- a mixed array's non-primitive members can't be silently
      # elided without misrepresenting the option.
      def array_value_for(value)
        stringified = value.map { |element| element.is_a?(Symbol) ? element.to_s : element }
        stringified.all? { |element| element.is_a?(String) || element.is_a?(Numeric) } ? stringified : nil
      end
    end
  end
end
