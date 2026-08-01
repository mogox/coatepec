# frozen_string_literal: true

class Owner < ApplicationRecord
  has_many :widgets, dependent: :destroy

  validates :name, presence: true
end
