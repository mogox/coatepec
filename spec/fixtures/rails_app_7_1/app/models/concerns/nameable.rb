# frozen_string_literal: true

# Declares the same presence validation Owner declares itself, so rails_model sees a real duplicate.
# Not named `Named`: that resolves to ActiveRecord::Scoping::Named inside a model body, silently including nothing.
module Nameable
  extend ActiveSupport::Concern

  included do
    validates :name, presence: true
  end
end
