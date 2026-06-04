ENV["RAILS_ENV"] ||= "test"
require "simplecov"

SimpleCov.start("rails") do
  add_filter "/test/"
end

require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: Integer(ENV.fetch("RAILS_TEST_WORKERS", "1"), 10))

    # Add more helper methods to be used by all tests here...
  end
end
