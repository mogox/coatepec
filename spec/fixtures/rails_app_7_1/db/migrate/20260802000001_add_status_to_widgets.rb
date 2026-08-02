# frozen_string_literal: true

class AddStatusToWidgets < ActiveRecord::Migration[7.1]
  def change
    add_column :widgets, :status, :integer, default: 0, null: false
  end
end
