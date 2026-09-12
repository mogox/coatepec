# frozen_string_literal: true

module Coatepec
  module Introspection
    # Flattens a route set into application routes followed by one level of mounted-engine
    # routes with the mount path prefixed, the way `bin/rails routes` shows them.
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

      # Rails' own /rails/info routes; `bin/rails routes` hides them too. Guarded so unit-spec structs work.
      def internal?(route)
        route.respond_to?(:internal) && route.internal
      end

      # One level only, like RoutesInspector; an engine mounted at two paths appears under both.
      def engine_entries(route)
        return [] unless engine_mount?(route)

        engine = route.app.rack_app
        prefix = mount_prefix(route)
        name = engine_name(engine)
        inner_routes(engine).reject { |inner| internal?(inner) }
                            .map { |inner| Entry.new(inner, prefix + inner.path.spec.to_s, name) }
      end

      # A `format: true` mount would carry (.:format); the inner routes bring their own. chomp only
      # affects a mount at "/", whose junction is the one place a "//" could form.
      def mount_prefix(route)
        route.path.spec.to_s.sub(/\(\.:format\)\z/, "").chomp("/")
      end

      # Only a ::Rails::Engine subclass is expanded or named; nothing else ever gets .name called on it.
      def engine_mount?(route)
        route.respond_to?(:app) && route.app.respond_to?(:engine?) && route.app.engine? &&
          rails_engine?(route.app.rack_app)
      end

      def rails_engine?(rack_app)
        defined?(::Rails::Engine) && rack_app.is_a?(Class) && rack_app < ::Rails::Engine
      end

      # Class.new(Rails::Engine) has a nil name; a fixed label keeps its routes tagged and boot-stable.
      def engine_name(engine)
        engine.name || "(anonymous engine)"
      end

      # engine.routes is a RouteSet whose .routes holds the Journey routes; anything else stays unflattened.
      def inner_routes(engine)
        return [] unless engine.respond_to?(:routes)

        route_set = engine.routes
        route_set.respond_to?(:routes) ? route_set.routes : []
      end
    end
  end
end
