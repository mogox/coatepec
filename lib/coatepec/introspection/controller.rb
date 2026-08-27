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
        {
          name: klass.name,
          controller_path: klass.controller_path,
          actions: action_names(klass).map { |action| { name: action, routes: [] } },
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
    end
  end
end
