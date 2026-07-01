ENV["RAILS_ENV"] ||= "test"
require "simplecov"

SimpleCov.start("rails") do
  add_filter "/test/"
end

require_relative "../config/environment"
require "rails/test_help"

module StudyContentReset
  def reset_study_tables!
    ContentSyncRun.delete_all if defined?(ContentSyncRun)
    CheckpointAttempt.delete_all
    ReviewSchedule.delete_all
    Reminder.delete_all
    MisconceptionEvent.delete_all
    SimulationAttempt.delete_all
    LearningRecord.delete_all
    StudyMission.delete_all
    Checkpoint.delete_all
    StudyBlock.delete_all
    StudyProgress.delete_all
    StudyDocument.delete_all
  end
end

module QueryCounter
  IGNORED_SQL_PAYLOAD_NAMES = %w[SCHEMA CACHE].freeze
  IGNORED_SQL_PREFIXES = [ /\ABEGIN/i, /\ACOMMIT/i, /\AROLLBACK/i, /\ASAVEPOINT/i, /\ARELEASE SAVEPOINT/i ].freeze

  def count_queries
    count = 0
    callback = lambda do |_name, _started, _finished, _unique_id, payload|
      next if IGNORED_SQL_PAYLOAD_NAMES.include?(payload[:name])
      next if IGNORED_SQL_PREFIXES.any? { |pattern| payload[:sql].match?(pattern) }

      count += 1
    end

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      yield
    end

    count
  end
end

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: Integer(ENV.fetch("RAILS_TEST_WORKERS", "1"), 10))

    # Add more helper methods to be used by all tests here...
    include StudyContentReset
    include QueryCounter
  end
end

class ActionDispatch::IntegrationTest
  include StudyContentReset
  include QueryCounter
end
