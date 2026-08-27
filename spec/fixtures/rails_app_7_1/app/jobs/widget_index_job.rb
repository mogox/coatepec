# frozen_string_literal: true

# Net::OpenTimeout isn't guaranteed loaded by a minimal Rails boot -- net/http
# is a default gem, not something Rails itself requires -- so it's required
# explicitly here rather than relying on it having been pulled in as a side
# effect of some other gem.
require "net/http"

class WidgetIndexJob < ApplicationJob
  queue_as :low_priority

  retry_on Net::OpenTimeout, wait: 5.seconds, attempts: 3
  discard_on ActiveJob::DeserializationError

  before_perform :log_start
  around_perform { |_job, block| block.call }

  def perform(widget_id)
    Widget.find_by(id: widget_id)
  end

  private

  def log_start
    Rails.logger.info("WidgetIndexJob starting")
  end
end
