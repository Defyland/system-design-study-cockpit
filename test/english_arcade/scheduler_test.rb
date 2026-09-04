# frozen_string_literal: true

require_relative "arcade_test_helper"

class EnglishArcadeSchedulerTest < Minitest::Test
  def test_retrievability_and_produce_interval
    assert_equal 1.0, EnglishArcade::Scheduler.retrievability(stability: 3, elapsed_days: 0)
    assert_in_delta 3.0, EnglishArcade::Scheduler.interval_days(stability: 3, stage: :produce), 0.0001
  end

  def test_lapse_clamps_and_is_due_now
    now = Time.utc(2026, 9, 4, 12)
    result = EnglishArcade::Scheduler.review(
      state: { stability: 20, difficulty: 5, lapses: 2, last_reviewed_at: now - 86_400 },
      rating: 1, stage: :produce, reviewed_at: now
    )

    assert_equal "relearning", result.fetch("status")
    assert_equal 3.0, result.fetch("stability")
    assert_equal 3, result.fetch("lapses")
    assert_equal now, result.fetch("due_at")
  end

  def test_fuzz_is_deterministic_and_relearn_success_does_not_grow
    now = Time.utc(2026, 9, 4, 12)
    assert_equal EnglishArcade::Scheduler.fuzz("card"), EnglishArcade::Scheduler.fuzz("card")
    result = EnglishArcade::Scheduler.review(
      state: { stability: 4, difficulty: 6, last_reviewed_at: now - 86_400 },
      rating: 3, stage: :cloze, reviewed_at: now, attempt_no: 2, seed: "card"
    )

    assert_equal 4.0, result.fetch("stability")
  end

  def test_boss_round_never_changes_stability_and_miss_is_due_now
    now = Time.utc(2026, 9, 4, 12)
    state = { stability: 7, difficulty: 4, due_at: now + 86_400, last_reviewed_at: now - 86_400 }
    pass = EnglishArcade::Scheduler.review(state: state, rating: 4, stage: :recognize, reviewed_at: now, boss: true)
    miss = EnglishArcade::Scheduler.review(state: state, rating: 1, stage: :recognize, reviewed_at: now, boss: true)

    assert_equal 7.0, pass.fetch("stability")
    assert_equal state.fetch(:due_at), pass.fetch("due_at")
    assert_equal 7.0, miss.fetch("stability")
    assert_equal now, miss.fetch("due_at")
  end
end
