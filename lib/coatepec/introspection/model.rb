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

      def build_metadata(klass)
        {
          name: klass.name,
          table_name: klass.table_name,
          primary_key: klass.primary_key,
          abstract_class: klass.abstract_class? || false,
          columns: columns_for(klass),
          associations: associations_for(klass),
          validators: validators_for(klass)
        }
      end

      private

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
          class_name: assoc.klass.name,
          foreign_key: assoc.foreign_key.to_s,
          through: assoc.through_reflection&.name&.to_s,
          polymorphic: assoc.polymorphic? || false
        }
      end

      def validators_for(klass)
        klass.validators.first(MAX_ITEMS).map do |validator|
          { name: validator.class.name, attributes: validator.attributes.map(&:to_s), options: validator.options }
        end
      end
    end
  end
end
