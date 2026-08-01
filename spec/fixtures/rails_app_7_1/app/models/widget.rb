# frozen_string_literal: true

class Widget < ApplicationRecord
  belongs_to :owner
  has_many :notes, as: :notable

  validates :name, presence: true
end
