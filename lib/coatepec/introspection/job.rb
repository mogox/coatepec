# frozen_string_literal: true

module Coatepec
  module Introspection
    # Returns bounded ActiveJob class metadata for a single job, for the
    # rails_job MCP tool. Pure reflection over an already-loaded, already-gated
    # class -- no job execution, no enqueuing, no queue adapter access.
    class Job
      NAME_PATTERN = /\A[A-Z]\w*(?:::[A-Z]\w*)*\z/
      MAX_ITEMS = 200

      def initialize(name)
        @name = name
      end

      def call
        validate_name!
        klass = resolve!
        validate_active_job!(klass)
        build_metadata(klass)
      end

      private

      def validate_name!
        return if @name.is_a?(String) && NAME_PATTERN.match?(@name)

        raise Coatepec::Error.new(:invalid_job_name, "#{@name.inspect} is not a valid constant name")
      end

      def resolve!
        ::ActiveSupport::Inflector.safe_constantize(@name) ||
          raise(Coatepec::Error.new(:job_not_found, "#{@name} could not be resolved"))
      end

      def validate_active_job!(klass)
        return if klass.is_a?(Class) && klass < ::ActiveJob::Base

        raise Coatepec::Error.new(:not_active_job, "#{@name} is not an ActiveJob job")
      end

      def build_metadata(klass)
        {
          name: klass.name,
          queue_name: queue_name_for(klass),
          queue_priority: klass.priority,
          callbacks: callbacks_for(klass),
          rescued_exceptions: rescued_exceptions_for(klass)
        }
      end

      # klass.queue_name (the class-level reader) returns an *unevaluated
      # Proc* -- `-> { self.class.default_queue_name }` -- for any job that
      # never called `queue_as`; only the instance method evaluates that
      # default. `.new` with no arguments is a safe, side-effect-free
      # constructor call (no perform, no enqueue) -- the class was already
      # gated by validate_active_job! before this runs, so this isn't the
      # "arbitrary method dispatch" the project's security boundary is about.
      def queue_name_for(klass)
        klass.new.queue_name
      end

      def callbacks_for(klass)
        klass._perform_callbacks.first(MAX_ITEMS).map do |callback|
          { kind: callback.kind.to_s, filter: filter_description(callback.filter) }
        end
      end

      # A Proc's #to_s/#source_location would leak the target app's absolute
      # source file path and line number into the output -- the same concern
      # Coatepec::Introspection::SafeOptions already guards against for
      # validator options. A Symbol filter (the method-reference form, e.g.
      # `before_perform :log_start`) is safe to report as-is.
      def filter_description(filter)
        case filter
        when Symbol
          filter.to_s
        when Proc
          "(block)"
        else
          filter.class.name
        end
      end

      # retry_on/discard_on are both implemented as rescue_from(*exceptions)
      # { ... } under the hood (ActiveJob::Exceptions) -- the wait:/attempts:/
      # queue:/priority: options passed to either macro are closed over inside
      # the resulting Proc, not stored anywhere queryable. All that's
      # genuinely introspectable is *which* exception classes have some
      # handler registered, via ActiveSupport::Rescuable's own
      # `rescue_handlers` (an array of [exception_class_name, proc] pairs) --
      # this can't distinguish retry_on from discard_on from a plain
      # rescue_from, or show any of their options. See README for the
      # documented limitation.
      def rescued_exceptions_for(klass)
        klass.rescue_handlers.first(MAX_ITEMS).map(&:first).uniq
      end
    end
  end
end
