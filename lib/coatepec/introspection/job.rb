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
        unless defined?(::ActiveJob::Base)
          raise Coatepec::Error.new(:not_active_job, "ActiveJob is not loaded in this app")
        end
        return if klass.is_a?(Class) && klass < ::ActiveJob::Base

        raise Coatepec::Error.new(:not_active_job, "#{@name} is not an ActiveJob job")
      end

      def build_metadata(klass)
        {
          name: klass.name,
          queue_name: queue_name_for(klass),
          queue_priority: queue_priority_for(klass),
          callbacks: callbacks_for(klass),
          rescued_exceptions: rescued_exceptions_for(klass)
        }
      end

      # ActiveJob stores both `queue_name` and `priority` as class attributes
      # that can hold either a plain value or an unevaluated Proc (the block
      # form of `queue_as`/`queue_with_priority`), and the two fields are
      # unsafe in *opposite* directions: the class-level `queue_name` reader
      # below never executes app code (only the *instance* method does, via
      # `instance_exec` on the Proc), but it can return that Proc unevaluated
      # to the caller -- while the class-level `priority` reader in
      # queue_priority_for is equally safe from execution but would leak a
      # raw Proc straight into JSON.generate (Proc#to_s exposes the target
      # app's absolute source file path and line number, the exact leak
      # Introspection::SafeOptions and filter_description below both guard
      # against). Neither accessor is uniformly safe, so each field gets its
      # own explicit handling rather than one shared rule.
      #
      # ActiveJob's own default value for this class attribute is a single
      # shared lambda object installed on ActiveJob::Base by class_attribute
      # and inherited *by identity* by every subclass that never called
      # `queue_as` itself -- so a Proc that is not that exact object must be
      # an app-authored `queue_as { ... }` block, which must never be
      # instance_exec'd here.
      def queue_name_for(klass)
        raw = klass.queue_name
        return klass.queue_name_from_part(nil) if raw.equal?(::ActiveJob::Base.queue_name)
        return "(dynamic)" if raw.is_a?(Proc)

        raw
      end

      # See queue_name_for above for why this field needs separate handling:
      # `queue_with_priority { ... }` stores the raw block as `klass.priority`,
      # and that Proc must never reach JSON.generate unfiltered.
      def queue_priority_for(klass)
        raw = klass.priority
        raw.is_a?(Proc) ? "(block)" : raw
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
        klass.rescue_handlers.first(MAX_ITEMS).map(&:first).compact.uniq
      end
    end
  end
end
