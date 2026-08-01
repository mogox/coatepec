# frozen_string_literal: true

require "active_support/inflector"

module Coatepec
  module Introspection
    # Returns bounded ActiveRecord schema and class metadata for a single
    # model, for the rails_model MCP tool. No records, no SQL beyond schema
    # reflection, no method dispatch on the resolved class beyond pure
    # introspection APIs.
    class Model
      NAME_PATTERN = /\A[A-Z]\w*(?:::[A-Z]\w*)*\z/
      MAX_ITEMS = 200

      def initialize(name)
        @name = name
      end

      def call
        validate_name!
        klass = resolve!
        validate_active_record!(klass)
        build_metadata(klass)
      end

      private

      # An abstract class (e.g. ApplicationRecord) has no real table, so
      # table_name/primary_key/columns all raise if called against it --
      # report empty/nil table data instead of crashing. Validators aren't
      # table-dependent, so those are always attempted.
      def build_metadata(klass)
        abstract = klass.abstract_class?
        {
          name: klass.name,
          table_name: abstract ? nil : klass.table_name,
          primary_key: abstract ? nil : klass.primary_key,
          abstract_class: abstract,
          columns: abstract ? [] : columns_for(klass),
          associations: abstract ? [] : associations_for(klass),
          validators: validators_for(klass)
        }
      end

      def validate_name!
        return if @name.is_a?(String) && NAME_PATTERN.match?(@name)

        raise Coatepec::Error.new(:invalid_model_name, "#{@name.inspect} is not a valid constant name")
      end

      def resolve!
        ::ActiveSupport::Inflector.safe_constantize(@name) ||
          raise(Coatepec::Error.new(:model_not_found, "#{@name} could not be resolved"))
      end

      def validate_active_record!(klass)
        return if klass.is_a?(Class) && klass < ::ActiveRecord::Base

        raise Coatepec::Error.new(:not_active_record_model, "#{@name} is not an ActiveRecord model")
      end

      def columns_for(klass)
        klass.columns.first(MAX_ITEMS).map do |column|
          { name: column.name, type: column.type.to_s, sql_type: column.sql_type, null: column.null,
            default: column.default }
        end
      end

      def associations_for(klass)
        klass.reflect_on_all_associations.first(MAX_ITEMS).map { |assoc| build_association_data(assoc) }
      end

      def build_association_data(assoc)
        {
          name: assoc.name.to_s,
          macro: assoc.macro.to_s,
          class_name: association_class_name(assoc),
          foreign_key: assoc.foreign_key.to_s,
          through: assoc.through_reflection&.name&.to_s,
          polymorphic: assoc.polymorphic? || false
        }
      end

      # A polymorphic belongs_to has no single fixed target class (assoc.klass
      # raises ArgumentError for those), and a reflection whose class_name
      # points at a constant that doesn't exist raises NameError. Both are
      # legitimate, introspectable states -- report class_name: nil rather
      # than letting either crash the whole call.
      def association_class_name(assoc)
        return nil if assoc.polymorphic?

        assoc.klass.name
      rescue NameError, ArgumentError
        nil
      end

      def validators_for(klass)
        klass.validators.first(MAX_ITEMS).map do |validator|
          {
            name: validator.class.name,
            attributes: validator.attributes.map(&:to_s),
            options: safe_options(validator.options)
          }
        end
      end

      def safe_options(options)
        options.filter_map do |key, value|
          safe_value = safe_option_value(value)
          [key.to_s, safe_value] unless safe_value.nil? && !value.nil?
        end.to_h
      end

      # Validator options can carry arbitrary Ruby objects (Proc for `if:`/
      # `unless:`, Regexp for `with:`, etc.). Those must never be JSON-
      # serialized as-is: Proc#to_s leaks the target app's absolute source
      # file path and line number. Only genuinely primitive values pass
      # through; anything else is silently dropped.
      def safe_option_value(value)
        case value
        when String, Numeric, TrueClass, FalseClass, NilClass
          value
        when Symbol
          value.to_s
        when Array
          value.all? { |v| v.is_a?(String) || v.is_a?(Numeric) } ? value : nil
        end
      end
    end
  end
end
