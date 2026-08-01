# frozen_string_literal: true

module Coatepec
  module Introspection
    # Returns a bounded, filterable list of the target Rails app's routes,
    # for the rails_routes MCP tool. Reads Rails.application.routes.routes
    # only -- no console, no request dispatch.
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
        self.class.rails_routes.map do |route|
          defaults = route.defaults
          {
            name: route.name&.to_s,
            verb: route.verb.to_s,
            path: route.path.spec.to_s,
            controller: defaults[:controller]&.to_s,
            action: defaults[:action]&.to_s
          }
        end
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
