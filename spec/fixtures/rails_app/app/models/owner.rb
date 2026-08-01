# frozen_string_literal: true

class Owner < ApplicationRecord
  has_many :widgets, dependent: :destroy

  validates :name, presence: true
  # length's `minimum:` option is a plain Integer and must survive into the
  # output. The `if:` option is a Proc -- Proc#to_s serializes the *host
  # app's* absolute source file path and line number, so it must never reach
  # the output (see Coatepec::Introspection::Model#safe_option_value).
  validates :name, length: { minimum: 1 }, if: -> { true }
  # `in:` holds an Array of Symbols -- the single most common non-scalar
  # option shape in Rails (`inclusion:`/`exclusion:`). It must survive as an
  # array of strings, exactly as a bare Symbol option value does.
  validates :name, exclusion: { in: %i[admin root] }
end
