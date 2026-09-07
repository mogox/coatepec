ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers. Kept exactly as `rails
    # new` generates it: coatepec's Minitest adapter must neutralise this
    # (PARALLEL_WORKERS=1) rather than rely on apps not having it.
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all
  end
end
