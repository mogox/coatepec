# frozen_string_literal: true

class DynamicWidgetJob < ApplicationJob
  queue_as { $coatepec_dynamic_queue_as_ran = true; "dynamic_queue" }
  queue_with_priority { 99 }

  def perform(widget_id)
    Widget.find_by(id: widget_id)
  end
end
