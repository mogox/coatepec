# frozen_string_literal: true

require_relative "model_resolver"

module Coatepec
  module Introspection
    # Returns bounded ActiveRecord schema and class metadata for a single
    # model, for the rails_model MCP tool. No records, no SQL beyond schema
    # reflection, no method dispatch on the resolved class beyond pure
    # introspection APIs.
    class Model
      FIELDS = %w[columns associations validators enums].freeze
      MAX_ITEMS = 200
      MAX_OPTION_VALUES = 20
      EMPTY_TABLE_METADATA = { table_name: nil, primary_key: nil, columns: [] }.freeze

      # Counts are always returned; lists are opt-in, so an omitted fields costs a few dozen bytes.
      def initialize(name, fields: nil)
        @name = name
        @fields = validate_fields!(fields || [])
      end

      def call
        klass = ModelResolver.call(@name)
        build_metadata(klass)
      end

      private

      # An abstract class (e.g. ApplicationRecord) has no real table, so table_name/primary_key/columns all raise
      # if called against it -- report empty/nil table data instead. abstract_class? is nil (not false) for a
      # concrete class on Rails 7.1 and false on 8.1, so normalize it for version-stable JSON. enums, like
      # validators, are in-memory class metadata needing no connection, so they are always collected.
      def build_metadata(klass)
        abstract = klass.abstract_class? || false
        table = abstract ? EMPTY_TABLE_METADATA : table_metadata(klass)
        sections = { columns: table[:columns], associations: abstract ? [] : associations_for(klass),
                     validators: validators_for(klass), enums: enums_for(klass) }
        { name: klass.name, table_name: table[:table_name], primary_key: table[:primary_key], abstract_class: abstract,
          counts: sections.transform_values(&:size) }.merge(sections.slice(*(FIELDS & @fields).map(&:to_sym)))
      end

      # The MCP schema enforces the enum; this guards the worker command against any other caller.
      def validate_fields!(fields)
        unless fields.is_a?(Array)
          raise Coatepec::Error.new(:invalid_model_fields, "fields must be an array, got #{fields.inspect}")
        end

        unknown = fields - FIELDS
        return fields if unknown.empty?

        raise Coatepec::Error.new(:invalid_model_fields,
                                  "fields must be among #{FIELDS.join(", ")}, got #{unknown.inspect}")
      end

      # A concrete model can still name a table that isn't there: a checkout
      # whose test database is behind on migrations, a view-backed model, a
      # model living in a database this process isn't connected to. That is
      # deliberately *not* folded into the abstract-class handling above --
      # an abstract class declares "I have no table", so empty column data is
      # the truthful answer for it, whereas a missing table is a real
      # mismatch the caller needs told about. Reporting it as a table with
      # zero columns would read as "this model has no columns", which is a
      # lie. It gets its own structured code instead of escaping as the
      # server's catch-all :internal_error. The exception's own message is
      # not interpolated: it carries driver-specific SQL text.
      def table_metadata(klass)
        { table_name: klass.table_name, primary_key: klass.primary_key, columns: columns_for(klass) }
      rescue ::ActiveRecord::StatementInvalid
        raise Coatepec::Error.new(
          :table_not_found,
          "#{@name}'s table (#{klass.table_name}) does not exist or could not be read"
        )
      end

      def columns_for(klass)
        klass.columns.first(MAX_ITEMS).map do |column|
          { name: column.name, type: column.type.to_s, sql_type: column.sql_type, null: column.null,
            default: column.default }
        end
      end

      def associations_for(klass)
        klass.reflect_on_all_associations.first(MAX_ITEMS).map { |assoc| safe_association_data(assoc) }
      end

      # build_association_data's own field-level rescues (association_class_name,
      # association_foreign_key) cover every failure mode seen in practice so
      # far, but ActiveRecord's reflection internals are large enough that
      # betting the whole rails_model call on having anticipated all of them
      # is optimistic -- a has_one/has_many :through a polymorphic belongs_to
      # is exactly the kind of case that wasn't anticipated until it crashed
      # this method outright (see association_foreign_key). This is the
      # boundary of last resort: one association's introspection failing
      # degrades just that entry instead of the whole model. It deliberately
      # does not rescue StandardError -- a NoMethodError here is a genuine
      # Coatepec bug (e.g. a typo), and letting that crash loudly beats
      # silently reporting it as "this association is fine, no data".
      def safe_association_data(assoc)
        build_association_data(assoc)
      rescue NameError, ArgumentError, ::ActiveRecord::ActiveRecordError => e
        degraded_association_data(assoc, e)
      end

      def degraded_association_data(assoc, error)
        {
          name: assoc.name.to_s, macro: assoc.macro.to_s, class_name: nil, foreign_key: nil, through: nil,
          polymorphic: nil, error: "#{error.class}: #{error.message}"
        }
      end

      def build_association_data(assoc)
        {
          name: assoc.name.to_s,
          macro: assoc.macro.to_s,
          class_name: association_class_name(assoc),
          foreign_key: association_foreign_key(assoc),
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

      # A has_one/has_many :through reflection whose `through:` target is
      # itself a polymorphic belongs_to has no single fixed class either --
      # ThroughReflection#foreign_key needs through_reflection.klass to find
      # the source reflection, and .klass on a polymorphic reflection always
      # raises ArgumentError (see association_class_name above). A dangling
      # class_name on the reflection itself still raises NameError the same
      # way. Report foreign_key: nil rather than letting either crash the
      # call.
      def association_foreign_key(assoc)
        assoc.foreign_key.to_s
      rescue NameError, ArgumentError
        nil
      end

      # Rails instantiates one validator per declaration; a concern and the model body often declare the same one.
      # De-duplicate on the raw validator: SafeOptions drops the Procs and Regexps that tell two apart.
      def validators_for(klass)
        klass.validators.uniq { |v| [v.class.name, v.attributes, v.options] }.first(MAX_ITEMS).map do |validator|
          {
            name: validator.class.name,
            attributes: validator.attributes.map(&:to_s),
            options: BoundedOptions.call(SafeOptions.call(validator.options), MAX_OPTION_VALUES)
          }
        end
      end

      def enums_for(klass)
        klass.defined_enums.first(MAX_ITEMS).map do |name, values|
          { name: name, values: values.first(MAX_ITEMS).to_h }
        end
      end
    end
  end
end
