module WidgetAdmin
  class AuditsController < ::ActionController::Base
    def index
      head :ok
    end

    def show
      head :ok
    end

    # Deliberately unrouted: the engine's routes.rb only routes index/show,
    # so rails_controller must list this under unroutable_actions.
    def export
      head :ok
    end
  end
end
