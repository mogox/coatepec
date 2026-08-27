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
require "json"
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

    before_action :require_login, only: %i[edit update]
    before_action :set_widget, except: [:index]
    around_action :with_timing
    after_action :notify, if: :notifiable?
    after_action :audit_trail, if: -> { true }
    before_action { head :ok }

    def index; end
    def show; end
    def edit; end
    def update; end
    def orphaned; end

    private

    def require_login; end
    def set_widget; end
    def with_timing; end
    def notify; end
    def audit_trail; end

    def notifiable?
      raise "callbacks must never be executed during introspection"
    end
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

  describe "callbacks" do
    subject(:callbacks) { described_class.new("ControllerFixtures::WidgetsController").call[:callbacks] }

    def callback_for(filter)
      callbacks.find { |cb| cb[:filter] == filter }
    end

    it "reports kind and a symbol filter by name" do
      expect(callback_for("require_login")[:kind]).to eq("before")
      expect(callback_for("with_timing")[:kind]).to eq("around")
    end

    # Load-bearing, not incidental: reaching @if/@unless needs a private ivar
    # read, and if a future Rails renames them, Array(nil) would silently
    # report every callback as unconditional. This assertion is what turns
    # that silent degradation into a loud CI failure.
    it "resolves only: to its action list" do
      expect(callback_for("require_login")[:only]).to eq(%w[edit update])
      expect(callback_for("require_login")[:except]).to be_nil
    end

    it "resolves except: to its action list, preserving author intent" do
      expect(callback_for("set_widget")[:except]).to eq(["index"])
      expect(callback_for("set_widget")[:only]).to be_nil
    end

    it "reports a Symbol if: condition by name" do
      expect(callback_for("notify")[:if]).to eq(["notifiable?"])
    end

    it "reports a Proc if: condition as (block), never its source path" do
      expect(callback_for("audit_trail")[:if]).to eq(["(block)"])
    end

    it "reports a block filter as (block)" do
      expect(callback_for("(block)")).not_to be_nil
    end

    it "leaves unconditional callbacks with empty conditions" do
      expect(callback_for("with_timing")).to include(only: nil, except: nil, if: [], unless: [])
    end

    it "never serializes a filesystem path anywhere in the response" do
      json = JSON.generate(described_class.new("ControllerFixtures::WidgetsController").call)
      expect(json).not_to include(__dir__)
      expect(json).not_to match(%r{/[\w.-]+/[\w.-]+\.rb})
    end

    it "does not execute callback conditions" do
      # notifiable? raises if called. Reaching this line at all proves it wasn't.
      expect { described_class.new("ControllerFixtures::WidgetsController").call }.not_to raise_error
    end
  end
end
