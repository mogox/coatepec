# frozen_string_literal: true

FIXTURE_APP_NAME = ENV.fetch("COATEPEC_FIXTURE_APP", "rails_app")
FIXTURE_APP_ROOT = File.expand_path("../fixtures/#{FIXTURE_APP_NAME}", __dir__).freeze
