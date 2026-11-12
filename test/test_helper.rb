ENV["RAILS_ENV"] ||= "test"
require "simplecov"
SimpleCov.start "rails" do
  skip "/app/tools/"
  minimum_coverage 90
end

require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"

WebMock.disable_net_connect!(allow: "127.0.0.1:19876")

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
