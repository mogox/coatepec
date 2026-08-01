# frozen_string_literal: true

class CreateOwnersAndWidgets < ActiveRecord::Migration[8.1]
  def change
    create_table :owners do |t|
      t.string :name, null: false
      t.timestamps
    end

    create_table :widgets do |t|
      t.string :name, null: false
      t.string :sku
      t.boolean :active, default: true, null: false
      t.references :owner, foreign_key: true
      t.timestamps
    end
  end
end
