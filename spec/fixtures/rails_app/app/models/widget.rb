# frozen_string_literal: true

class Widget < ApplicationRecord
  belongs_to :owner

  validates :name, presence: true
end
