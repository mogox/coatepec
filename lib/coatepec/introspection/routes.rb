# frozen_string_literal: true

require_relative "route_entries"

module Coatepec
  module Introspection
    # Returns a bounded, filterable list of the target app's routes for the rails_routes MCP tool: application
    # routes by default, mounted-engine routes on request. Reads route tables only -- no console, no dispatch.
    class Routes
      MAX_LIMIT = 200
      DEFAULT_LIMIT = 100
      ENGINE_FILTERS = %w[include exclude only].freeze
      # Engine CRUD scaffolding was two thirds of a typical match; the payload states what the default withheld.
      DEFAULT_ENGINES = "exclude"

      def initialize(query: nil, limit: DEFAULT_LIMIT, offset: 0, engines: DEFAULT_ENGINES)
        @query = query
        @limit = [limit || DEFAULT_LIMIT, MAX_LIMIT].min
        @offset = offset || 0
        @engines = validate_engines!(engines || DEFAULT_ENGINES)
      end

      def call
        matched, excluded = partitioned_items
        page(matched, excluded)
      end

      private

      def page(matched, excluded)
        {
          items: matched[@offset, @limit] || [],
          matched: matched.size,
          limit: @limit,
          offset: @offset,
          next_offset: next_offset_for(matched.size),
          engines: @engines,
          engines_excluded: excluded.size
        }
      end

      # The MCP schema already enforces the enum; this guards the worker command against any other caller.
      def validate_engines!(value)
        return value if ENGINE_FILTERS.include?(value)

        raise Coatepec::Error.new(:invalid_engines_filter,
                                  "engines must be one of #{ENGINE_FILTERS.join(", ")}, got #{value.inspect}")
      end

      # Spelled out so a caller never has to infer a follow-up page from matched > limit.
      # candidate > @offset guards limit 0, which would otherwise hand back the same offset forever.
      def next_offset_for(matched_count)
        candidate = @offset + @limit
        candidate > @offset && candidate < matched_count ? candidate : nil
      end

      # Query first, then the engine filter, so engines_excluded counts routes this exact query would have shown.
      def partitioned_items
        query_matches.partition { |item| engine_selected?(item) }
      end

      def query_matches
        items = all_items
        return items unless @query

        query_downcased = @query.downcase
        items.select { |item| item.values.compact.any? { |v| v.to_s.downcase.include?(query_downcased) } }
      end

      # An engine's mount route has engine: nil -- it is an application route and stays under "exclude".
      def engine_selected?(item)
        case @engines
        when "exclude" then item[:engine].nil?
        when "only" then !item[:engine].nil?
        else true
        end
      end

      def all_items
        RouteEntries.call(self.class.rails_routes).map { |entry| item_for(entry) }
      end

      # path comes off the entry: for an engine route it already carries the mount prefix.
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
