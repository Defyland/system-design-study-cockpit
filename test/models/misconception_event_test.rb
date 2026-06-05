require "test_helper"

class MisconceptionEventTest < ActiveSupport::TestCase
  test "requires a known misconception key" do
    event = MisconceptionEvent.new(
      source_kind: "checkpoint_attempt",
      source_id: 1,
      misconception_key: "unknown",
      severity: 1
    )

    assert_not event.valid?
    assert_includes event.errors.attribute_names, :misconception_key
  end
end
