# frozen_string_literal: true

module Coatepec
  module Introspection
    # Turns a rails_model name into an ActiveRecord class, or raises the structured error that says why not.
    module ModelResolver
      NAME_PATTERN = /\A[A-Z]\w*(?:::[A-Z]\w*)*\z/

      module_function

      def call(name)
        validate_name!(name)
        klass = ::ActiveSupport::Inflector.safe_constantize(name) ||
                raise(Coatepec::Error.new(:model_not_found, "#{name} could not be resolved"))
        validate_active_record!(name, klass)
        klass
      end

      def validate_name!(name)
        return if name.is_a?(String) && NAME_PATTERN.match?(name)

        raise Coatepec::Error.new(:invalid_model_name, "#{name.inspect} is not a valid constant name")
      end

      def validate_active_record!(name, klass)
        return if klass.is_a?(Class) && klass < ::ActiveRecord::Base

        raise Coatepec::Error.new(:not_active_record_model, "#{name} is not an ActiveRecord model")
      end
    end
  end
end
