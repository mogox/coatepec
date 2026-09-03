module Auditable
  extend ActiveSupport::Concern

  included do
    before_action :record_audit
  end

  # Deliberately public: Rails routes to any public controller method, so this
  # must appear in rails_controller's `actions`. Proves the tool surfaces
  # accidentally-routable methods rather than hiding them.
  def audit
    head :ok
  end

  private

  def record_audit; end
end
