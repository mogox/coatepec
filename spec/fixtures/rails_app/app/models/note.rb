# frozen_string_literal: true

class Note < ApplicationRecord
  belongs_to :notable, polymorphic: true

  # Goes *through* the polymorphic belongs_to above, rather than being one
  # itself. ThroughReflection#foreign_key needs through_reflection.klass to
  # find the source reflection, and .klass on a polymorphic reflection
  # always raises ArgumentError -- this reproduces the real crash that
  # Coatepec::Introspection::Model's safety net exists to degrade gracefully
  # instead of taking down the whole rails_model response for Note.
  has_one :notable_owner, through: :notable, source: :owner
end
