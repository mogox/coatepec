# frozen_string_literal: true

require_relative "route_entries"

module Coatepec
  module Introspection
    # Returns a bounded, filterable list of the target Rails app's routes,
    # for the rails_routes MCP tool. Reads Rails.application.routes.routes and
    # -- via RouteEntries -- the routes of every engine those routes mount,
    # skipping Rails' own internal routes, exactly as `bin/rails routes` does.
    # No console, no request dispatch.
    class Routes
      MAX_LIMIT = 200
      DEFAULT_LIMIT = 50

      def initialize(query: nil, limit: DEFAULT_LIMIT, offset: 0)
        @query = query
        @limit = [limit || DEFAULT_LIMIT, MAX_LIMIT].min
        @offset = offset || 0
      end

      def call
        matched = filtered_items
        {
          items: matched[@offset, @limit] || [],
          matched: matched.size,
          limit: @limit,
          offset: @offset
        }
      end

      private

      def filtered_items
        items = all_items
        return items unless @query

        query_downcased = @query.downcase
        items.select { |item| item.values.compact.any? { |v| v.to_s.downcase.include?(query_downcased) } }
      end

      def all_items
        RouteEntries.call(self.class.rails_routes).map { |entry| item_for(entry) }
      end

      # The path comes off the entry rather than the route: for an engine
      # route it is the inner path with the mount point prefixed onto it.
      def item_for(entry)
        route = entry.route
        defaults = route.defaults
        {
          name: route.name&.to_s,
          verb: route.verb.to_s,
          path: entry.path,
          controller: defaults[:controller]&.to_s,
          action: defaults[:action]&.to_s,
          engine: entry.engine
        }
      end

      # Isolated as a class method purely so unit tests can stub it without
      # booting Rails -- Rails.application.routes.routes is otherwise only
      # reachable with a real, booted application.
      # rubocop:disable Lint/IneffectiveAccessModifier
      def self.rails_routes
        Rails.application.routes.routes
      end
      # rubocop:enable Lint/IneffectiveAccessModifier
    end
  end
end
