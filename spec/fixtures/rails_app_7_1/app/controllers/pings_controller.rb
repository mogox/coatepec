# An ActionController::API controller, which is NOT an ActionController::Base
# descendant. Proves the Metal gate admits API-only controllers and that the
# concern slice resolves to ActionController::API for them.
class PingsController < ActionController::API
  def index
    head :ok
  end
end
