require "test_helper"

class ReminderTest < ActiveSupport::TestCase
  test "requires a unique source identity" do
    Reminder.create!(
      source_kind: "checkpoint",
      source_slug: "chapter-01:1",
      message: "Reveja o checkpoint.",
      priority: 2
    )

    duplicate = Reminder.new(
      source_kind: "checkpoint",
      source_slug: "chapter-01:1",
      message: "Texto atualizado.",
      priority: 3
    )

    assert_predicate duplicate, :invalid?
    assert_includes duplicate.errors[:source_slug], "has already been taken"
  end
end
