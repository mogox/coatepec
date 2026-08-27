class WidgetsController < ApplicationController
  include Auditable

  before_action :require_login, only: %i[edit update]
  before_action :set_widget, except: [:index]
  around_action :with_timing
  after_action :notify, if: :notifiable?
  after_action :audit_trail, if: -> { true }
  # Anonymous, so it must reduce to "(block)"; guarded by a named if:
  # condition unique to this controller so a test can pick this callback out
  # from among any other "(block)" before-callback the framework or a parent
  # controller may itself contribute (e.g. Rails 8's `allow_browser` compiles
  # to its own unconditional before_action block on ApplicationController).
  before_action(if: :widgets_own_block?) { head :ok }

  def index
    head :ok
  end

  def show
    head :ok
  end

  def edit
    head :ok
  end

  def update
    head :ok
  end

  # No route reaches this action; rails_controller must report it as
  # unroutable.
  def orphaned
    head :ok
  end

  private

  def require_login; end

  def set_widget; end

  def with_timing
    yield
  end

  def notify; end

  def audit_trail; end

  def widgets_own_block?
    true
  end

  # Raises if ever called. Introspection must never execute a callback
  # condition, so a passing spec proves it didn't.
  def notifiable?
    raise "callback conditions must never be executed during introspection"
  end
end
