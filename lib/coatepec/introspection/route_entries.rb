# frozen_string_literal: true

module Coatepec
  module Introspection
    # Flattens a Rails route set into a single list of entries: every
    # application route, followed by the routes of every engine mounted by
    # those routes, each with the mount path prefixed onto it.
    #
    # This deliberately mirrors ActionDispatch::Routing::RoutesInspector's
    # #load_engines_routes, which is what `bin/rails routes` shows: engines are
    # expanded one level only (an engine mounted inside an engine stays an
    # opaque mount route), and routes flagged `internal` -- Rails' own
    # /rails/info and friends -- are dropped at both levels. It diverges on one
    # point: Rails keys engines by endpoint, so an engine mounted at two paths
    # is listed once, whereas this emits that engine's routes under both mount
    # prefixes, because each prefixed path is a real, reachable URL.
    #
    # Every attribute beyond `path` is reached through a respond_to? guard.
    # Unit specs feed this class plain Structs and doubles standing in for
    # Journey routes, and no ActionDispatch constant is named here, so the
    # file loads and runs with no Rails booted at all.
    class RouteEntries
      Entry = Struct.new(:route, :path, :engine)

      def self.call(routes)
        new(routes).call
      end

      def initialize(routes)
        @routes = routes
      end

      def call
        visible = @routes.reject { |route| internal?(route) }

        visible.map { |route| Entry.new(route, route.path.spec.to_s, nil) } +
          visible.flat_map { |route| engine_entries(route) }
      end

      private

      def internal?(route)
        route.respond_to?(:internal) && route.internal
      end

      def engine_entries(route)
        return [] unless engine_mount?(route)

        rack_app = route.app.rack_app
        prefix = mount_prefix(route)
        name = engine_name(rack_app)
        inner_routes(rack_app).reject { |inner| internal?(inner) }.map do |inner|
          # squeeze collapses the double slash an engine mounted at "/" makes.
          Entry.new(inner, (prefix + inner.path.spec.to_s).squeeze("/"), name)
        end
      end

      # Defensive strip: ActionDispatch::Routing::Mapper#mount defaults to
      # `format: false`, so a real mount spec does not carry the `(.:format)`
      # suffix -- but a mount declared with `format: true` would, and the inner
      # routes supply their own suffix, so it must not survive into the prefix.
      def mount_prefix(route)
        route.path.spec.to_s.sub(/\(\.:format\)\z/, "")
      end

      def engine_mount?(route)
        route.respond_to?(:app) && route.app.respond_to?(:engine?) && route.app.engine?
      end

      # rack_app IS the engine class (not an instance of it), so its own .name
      # is the engine name -- .class.name here would yield "Class".
      #
      # An anonymous engine (Class.new(::Rails::Engine) mounted directly) has a
      # nil name, which would make its routes indistinguishable from
      # application ones and break the "non-nil engine means engine route"
      # invariant, so it falls back to #inspect -- the same fallback Rails'
      # RouteWrapper#endpoint uses for an unnamed endpoint.
      def engine_name(rack_app)
        name = rack_app.is_a?(Class) ? rack_app.name : rack_app.class.name
        name || rack_app.inspect
      end

      # An engine's .routes is an ActionDispatch::Routing::RouteSet, whose own
      # .routes is the enumerable of Journey routes. Anything else mounted
      # under an engine-shaped app is left unflattened rather than raising.
      def inner_routes(rack_app)
        return [] unless rack_app.respond_to?(:routes)

        route_set = rack_app.routes
        route_set.respond_to?(:routes) ? route_set.routes : []
      end
    end
  end
end
