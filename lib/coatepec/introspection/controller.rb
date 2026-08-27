# frozen_string_literal: true

module Coatepec
  module Introspection
    # Returns bounded ActionController class metadata for a single controller,
    # for the rails_controller MCP tool. Pure reflection over an already-loaded,
    # already-gated class -- no request dispatch, no action execution, and no
    # evaluation of app-authored callback conditions.
    # rubocop:disable Metrics/ClassLength -- Task 3 (route cross-referencing)
    # adds genuinely cohesive functionality: routes_by_action, grouped_routes,
    # route_data, and rails_routes exist solely to serve this class's single
    # responsibility (reflect on one controller). Splitting them into a
    # separate collaborator class would fragment that one responsibility
    # across files for no readability gain, only to satisfy a line count.
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
        routes = routes_by_action(klass)
        {
          name: klass.name, controller_path: klass.controller_path,
          actions: actions.map { |action| { name: action, routes: routes.fetch(action, []) } },
          unroutable_actions: actions.reject { |action| routes.key?(action) },
          routes_without_action: routes_without_action(klass, routes),
          callbacks: callbacks_for(klass, actions), concerns: concerns_for(klass)
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

      # controller_path is the public, correctly-namespaced key Rails itself
      # stores in a route's defaults (Admin::ReportsController =>
      # "admin/reports"), so matching on it needs no name munging.
      #
      # Only Rails.application.routes is read, so a controller mounted inside
      # an engine will report its actions as unroutable even though the
      # engine's own route set reaches them. Introspection::Routes has exactly
      # the same boundary today; it is documented in the README rather than
      # silently absorbed.
      # A route whose defaults[:action] is nil or empty (a mount or redirect)
      # is skipped, not recorded under an empty-string action.
      def routes_by_action(klass)
        grouped_routes(klass).transform_values { |list| list.first(MAX_ITEMS).map { |route| route_data(route) } }
      end

      def grouped_routes(klass)
        path = klass.controller_path
        matching = self.class.rails_routes.select { |route| route.defaults[:controller].to_s == path }
        matching.group_by { |route| route.defaults[:action].to_s }.reject { |action, _| action.empty? }
      end

      # Differenced against the controller's full action_methods set, not the
      # (possibly truncated-to-MAX_ITEMS) displayed `actions` list -- a
      # controller with more than MAX_ITEMS action methods would otherwise
      # have every route whose action fell past the truncation point reported
      # here as a false positive, in the field the README calls the tool's
      # most actionable output. Bounded to MAX_ITEMS like every other
      # collection in this payload; `grouped_routes` itself caps each route
      # *list* but not its key count, so this is where that cap belongs.
      def routes_without_action(klass, routes)
        defined_actions = klass.action_methods.map(&:to_s)
        (routes.keys - defined_actions).sort.first(MAX_ITEMS)
      end

      # path keeps Rails' raw spec, `(.:format)` suffix included, so a path
      # string here is byte-identical to the same route as reported by
      # rails_routes. Stripping it would make the two tools disagree about the
      # same route.
      def route_data(route)
        { verb: route.verb.to_s, path: route.path.spec.to_s, route_name: route.name&.to_s }
      end

      # Isolated as a class method purely so unit tests can stub it without
      # booting Rails -- Rails.application.routes.routes is otherwise only
      # reachable with a real, booted application. Mirrors
      # Introspection::Routes.rails_routes.
      # rubocop:disable Lint/IneffectiveAccessModifier
      def self.rails_routes
        Rails.application.routes.routes
      end
      # rubocop:enable Lint/IneffectiveAccessModifier

      # Gated on Metal, not Base/API, so a bare ActionController::Metal
      # subclass -- which passes validate_action_controller!'s class gate but
      # does not include AbstractController::Callbacks, unlike Base and API --
      # gets an empty callback list instead of a NoMethodError.
      def callbacks_for(klass, actions)
        return [] unless klass.respond_to?(:_process_action_callbacks)

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
          only: matched_actions(ifs, actions, :all?),
          except: matched_actions(unlesses, actions, :any?),
          if: plain_conditions(ifs),
          unless: plain_conditions(unlesses)
        }
      end

      # nil (not []) when there is no ActionFilter at all: "this callback is
      # unrestricted" and "this callback is restricted to no actions" are
      # different facts and must not serialize identically.
      #
      # A chain routinely carries *more than one* ActionFilter: skip_callback
      # (ActiveSupport::Callbacks::Callback#merge_conditional_options)
      # concatenates a skip's normalized only:/except: onto the callback's
      # existing @if/@unless chain rather than replacing it, so any
      # `skip_before_action ..., only:`/`except:` leaves two ActionFilters
      # behind. A callback only runs when *every* @if condition holds and
      # *none* of its @unless conditions hold (ActiveSupport::Callbacks'
      # run_callbacks ANDs @if and ANDs the negation of each @unless), so:
      # only: is every @if ActionFilter's matches intersected (combinator
      # :all? -- all must hold for the action to run the callback), and
      # except: is every @unless ActionFilter's matches unioned (combinator
      # :any? -- any one holding is enough to skip it). Keeping only the
      # first ActionFilter in the chain (as a naive `find` would) silently
      # drops every skip layered on top of it, which always biases toward
      # over-reporting protection -- exactly backwards for a tool whose job is
      # to answer "is this action protected?".
      def matched_actions(conditions, actions, combinator)
        filters = conditions.select { |condition| action_filter?(condition) }
        return nil if filters.empty?

        actions.select do |action|
          filters.public_send(combinator) { |filter| filter.match?(CallbackProbe.new(action, false)) }
        end
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

      # A Symbol filter (the method-reference form, e.g.
      # `before_action :require_login`) is a method reference and safe to
      # report by name; a Proc must never be serialized, because Proc#to_s
      # leaks the app's absolute source path, so it is reduced to "(block)"
      # instead. Introspection::SafeOptions guards the same class of leak
      # elsewhere, by silently dropping Procs from an options hash rather than
      # substituting a placeholder -- a different mechanism for the same rule.
      def filter_description(filter)
        case filter
        when Symbol then filter.to_s
        when Proc then "(block)"
        else filter.class.name || "(anonymous filter class)"
        end
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
