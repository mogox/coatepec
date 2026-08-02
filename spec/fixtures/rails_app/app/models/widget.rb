# frozen_string_literal: true

class Widget < ApplicationRecord
  belongs_to :owner
  has_many :notes, as: :notable

  enum :status, { draft: 0, published: 1 }

  validates :name, presence: true
end
