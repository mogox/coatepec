# frozen_string_literal: true

module Coatepec
  module Introspection
    # Returns bounded ActionController class metadata for a single controller,
    # for the rails_controller MCP tool. Pure reflection over an already-loaded,
    # already-gated class -- no request dispatch, no action execution, and no
    # evaluation of app-authored callback conditions.
    class Controller
      NAME_PATTERN = /\A[A-Z]\w*(?:::[A-Z]\w*)*\z/
      MAX_ITEMS = 200

      # AbstractController::Callbacks::ActionFilter#match? reads exactly two
      # things off the controller it is handed: `action_name`, and (Rails 7.1+)
      # `raise_on_missing_callback_actions`. That second one must be false --
      # when true, match? raises ActionNotFound for any action named in `only:`
      # that the controller doesn't define, which is precisely the drift this
      # tool exists to *report*, so it must never raise here. This Struct is
      # the entire controller surface match? touches; nothing on it can
      # execute application code.
      CallbackProbe = Struct.new(:action_name, :raise_on_missing_callback_actions)

      def initialize(name)
        @name = name
      end

      def call
        validate_name!
        klass = resolve!
        validate_action_controller!(klass)
        build_metadata(klass)
      end

      private

      def build_metadata(klass)
        actions = action_names(klass)
        {
          name: klass.name,
          controller_path: klass.controller_path,
          actions: actions.map { |action| { name: action, routes: [] } },
          callbacks: callbacks_for(klass, actions),
          concerns: concerns_for(klass)
        }
      end

      def validate_name!
        return if @name.is_a?(String) && NAME_PATTERN.match?(@name)

        raise Coatepec::Error.new(:invalid_controller_name, "#{@name.inspect} is not a valid constant name")
      end

      def resolve!
        ::ActiveSupport::Inflector.safe_constantize(@name) ||
          raise(Coatepec::Error.new(:controller_not_found, "#{@name} could not be resolved"))
      end

      # Gate on Metal, not Base: an ActionController::API controller is not a
      # Base descendant, so gating on Base would reject every API-only app.
      def validate_action_controller!(klass)
        unless defined?(::ActionController::Metal)
          raise Coatepec::Error.new(:not_action_controller, "ActionController is not loaded in this app")
        end
        return if klass.is_a?(Class) && klass < ::ActionController::Metal

        raise Coatepec::Error.new(:not_action_controller, "#{@name} is not an ActionController controller")
      end

      # action_methods is a Set of Strings. Sorted for stable output across
      # runs. A public method contributed by a concern legitimately appears
      # here -- Rails really would route to it, so surfacing it is the point,
      # not a leak to filter out.
      def action_names(klass)
        klass.action_methods.to_a.map(&:to_s).sort.first(MAX_ITEMS)
      end

      # Slice the ancestor chain at the first ActionController::* class in it:
      # ActionController::Base for a normal controller, ActionController::API
      # for an API-only one. Everything before that point was inserted by the
      # app, so this needs no denylist of the ~60 framework modules below it.
      # Anonymous modules have a nil name and are dropped.
      def concerns_for(klass)
        base = framework_base(klass)
        klass.ancestors
             .take_while { |mod| mod != base }
             .reject { |mod| mod.is_a?(Class) }
             .filter_map(&:name)
             .first(MAX_ITEMS)
      end

      def framework_base(klass)
        klass.ancestors.find do |mod|
          mod.is_a?(Class) && mod.name.to_s.start_with?("ActionController::")
        end
      end

      def callbacks_for(klass, actions)
        klass._process_action_callbacks.first(MAX_ITEMS).map do |callback|
          conditions_for(callback, actions)
            .merge(kind: callback.kind.to_s, filter: filter_description(callback.filter))
        end
      end

      # only:/except: do not survive as readable options. Rails compiles both
      # into an ActionFilter and distinguishes them purely by *placement*: the
      # `only:` filter lands in the callback's @if chain, the `except:` one in
      # its @unless chain. Intent is therefore recovered from which chain the
      # object sits in, not from the object itself.
      #
      # Reaching those chains needs instance_variable_get: Callback exposes
      # `kind` and `filter` publicly but has no reader for @if/@unless. That
      # single private read is unavoidable; having taken it, the action set is
      # then read through ActionFilter's *public* match? rather than a second
      # private read of its @actions, so this keeps working if Rails changes
      # how ActionFilter stores them.
      def conditions_for(callback, actions)
        ifs = Array(callback.instance_variable_get(:@if))
        unlesses = Array(callback.instance_variable_get(:@unless))
        {
          only: matched_actions(ifs, actions),
          except: matched_actions(unlesses, actions),
          if: plain_conditions(ifs),
          unless: plain_conditions(unlesses)
        }
      end

      # nil (not []) when there is no ActionFilter at all: "this callback is
      # unrestricted" and "this callback is restricted to no actions" are
      # different facts and must not serialize identically.
      def matched_actions(conditions, actions)
        filter = conditions.find { |condition| action_filter?(condition) }
        return nil unless filter

        actions.select { |action| filter.match?(CallbackProbe.new(action, false)) }
      end

      def action_filter?(condition)
        defined?(::AbstractController::Callbacks::ActionFilter) &&
          condition.is_a?(::AbstractController::Callbacks::ActionFilter)
      end

      # The conditions that are *not* only:/except: -- a real `if:`/`unless:`.
      # A Symbol is a method reference and safe to name; a Proc must never be
      # serialized (Proc#to_s leaks the app's absolute source path).
      def plain_conditions(conditions)
        conditions.reject { |condition| action_filter?(condition) }
                  .map { |condition| filter_description(condition) }
      end

      # Mirrors Introspection::Model#filter_description: a Symbol filter (the
      # method-reference form, e.g. `before_action :require_login`) is safe to
      # report as-is; a Proc is reduced to "(block)" so no source path leaks.
      def filter_description(filter)
        case filter
        when Symbol then filter.to_s
        when Proc then "(block)"
        else filter.class.name
        end
      end
    end
  end
end
