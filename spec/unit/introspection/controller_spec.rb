# frozen_string_literal: true

require "spec_helper"
require "coatepec/introspection/controller"

# Introspection::Controller resolves constants through ActiveSupport and
# reflects over real ActionController classes, relying on Rails already being
# booted in this gem's real architecture. These examples build genuine
# controller classes instead of doubles -- the whole point is to assert
# against Rails' actual reflection APIs, which a double would not exercise.
# actionpack is guaranteed present: railties (a declared runtime dependency,
# ">= 7.1", "< 8.2") depends on actionpack at the same version.
require "action_controller"
require "active_support/inflector"

module ControllerFixtures
  module Auditable
    extend ActiveSupport::Concern
    # Deliberately public: Rails treats any public method as routable, so this
    # must surface in `actions`. See "action_methods reports a concern's public
    # method" in the design doc.
    def audit; end
  end

  module Throttled; end

  class BaseController < ActionController::Base; end

  class WidgetsController < BaseController
    include Auditable
    def index; end
    def show; end
    def edit; end
    def update; end
    def orphaned; end
  end

  class ThingsController < ActionController::API
    include Throttled
    def index; end
  end

  class NotAController; end
end

RSpec.describe Coatepec::Introspection::Controller do
  describe "name validation" do
    it "raises invalid_controller_name for a lowercase-starting name" do
      expect { described_class.new("widgetsController").call }
        .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:invalid_controller_name) }
    end

    it "raises invalid_controller_name for a name containing invalid characters" do
      expect { described_class.new("WidgetsController; puts 1").call }
        .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:invalid_controller_name) }
    end

    it "raises invalid_controller_name for non-String and empty input" do
      [nil, 123, ""].each do |bad_name|
        expect { described_class.new(bad_name).call }
          .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:invalid_controller_name) }
      end
    end

    it "accepts a well-formed namespaced name (failing later, on resolution)" do
      expect { described_class.new("Admin::NopeController").call }
        .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:controller_not_found) }
    end
  end

  describe "class gating" do
    it "raises not_action_controller for a plain class" do
      expect { described_class.new("ControllerFixtures::NotAController").call }
        .to raise_error(Coatepec::Error) { |e| expect(e.code).to eq(:not_action_controller) }
    end

    it "accepts an ActionController::API controller" do
      result = described_class.new("ControllerFixtures::ThingsController").call
      expect(result[:name]).to eq("ControllerFixtures::ThingsController")
    end
  end

  describe "actions" do
    subject(:result) { described_class.new("ControllerFixtures::WidgetsController").call }

    it "returns the controller's action names, sorted" do
      expect(result[:actions].map { |a| a[:name] })
        .to eq(%w[audit edit index orphaned show update])
    end

    it "reports controller_path" do
      expect(result[:controller_path]).to eq("controller_fixtures/widgets")
    end
  end

  describe "concerns" do
    it "includes both own and inherited app concerns, and no framework modules" do
      result = described_class.new("ControllerFixtures::WidgetsController").call
      expect(result[:concerns]).to eq(["ControllerFixtures::Auditable"])
      expect(result[:concerns].grep(/^ActionController::/)).to be_empty
    end

    it "slices at ActionController::API for an API controller" do
      result = described_class.new("ControllerFixtures::ThingsController").call
      expect(result[:concerns]).to eq(["ControllerFixtures::Throttled"])
    end
  end
end
