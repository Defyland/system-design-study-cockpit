# frozen_string_literal: true

require_relative "arcade_test_helper"

class EnglishArcadeExerciseGraderTest < Minitest::Test
  def test_recognition_uses_server_item_not_client_correctness
    exercise = factory.build(sample_item, stage: :recognize)
    correct = exercise.dig("payload", "options").find { |option| option.fetch("text") == sample_item.fetch("best_answer") }
    grade = EnglishArcade::ExerciseGrader.grade(exercise, item: sample_item, response: correct.fetch("id"), response_ms: 5_000)

    assert_equal true, grade.fetch("correct")
    assert_equal 3, grade.fetch("rating")
  end

  def test_wrong_choice_reports_its_authored_axis
    exercise = factory.build(sample_item, stage: :recognize)
    wrong_text = sample_item.fetch("distractors").find { |choice| choice.fetch("trap") == "grammar" }.fetch("text")
    selected = exercise.dig("payload", "options").find { |option| option.fetch("text") == wrong_text }
    grade = EnglishArcade::ExerciseGrader.grade(exercise, item: sample_item, response: selected.fetch("id"), response_ms: 1_000)

    assert_equal false, grade.fetch("correct")
    assert_equal 1, grade.fetch("rating")
    assert_equal "grammar", grade.fetch("trap_axis")
  end

  def test_trap_timing_cannot_inflate_srs_rating
    exercise = factory.build(sample_item, stage: :trap)
    expected = sample_item.fetch("distractors").find { |choice| choice.fetch("text") == exercise.dig("payload", "distractor") }.fetch("trap")
    fast = EnglishArcade::ExerciseGrader.grade(exercise, item: sample_item, response: expected, response_ms: 1)
    slow = EnglishArcade::ExerciseGrader.grade(exercise, item: sample_item, response: expected, response_ms: 60_000)

    assert_equal 3, fast.fetch("rating")
    assert_equal fast, slow
  end

  def test_rebuild_accepts_exact_order_and_marks_adjacent_swap_hard
    exercise = factory.build(sample_item, stage: :rebuild)
    expected = EnglishArcade::TextTools.clause_chunks(sample_item.fetch("best_answer"))
    ids = expected.map { |text| exercise.dig("payload", "chunks").find { |chunk| chunk.fetch("text") == text }.fetch("id") }

    exact = EnglishArcade::ExerciseGrader.grade(exercise, item: sample_item, response: ids)
    hard = EnglishArcade::ExerciseGrader.grade(exercise, item: sample_item, response: ids.rotate(1))
    assert_equal 3, exact.fetch("rating")
    assert_equal 1, hard.fetch("rating")
  end

  def test_speak_allows_self_rated_shadowing_without_a_transcript_but_caps_at_good
    exercise = factory.build(sample_item, stage: :speak)
    grade = EnglishArcade::ExerciseGrader.grade(exercise, item: sample_item, response_text: "", self_rating: 4)

    assert_equal true, grade.fetch("correct")
    assert_equal 3, grade.fetch("rating")
    assert_equal true, grade.dig("details", "self_rated")
  end

  def test_produce_still_requires_answer_text
    exercise = factory.build(sample_item, stage: :produce)
    grade = EnglishArcade::ExerciseGrader.grade(exercise, item: sample_item, response_text: "", self_rating: 4)

    assert_equal false, grade.fetch("correct")
    assert_equal 1, grade.fetch("rating")
  end

  def test_feynman_requires_both_an_explanation_and_a_passing_self_rating
    exercise = factory.build(sample_item, stage: :feynman)
    empty = EnglishArcade::ExerciseGrader.grade(exercise, item: sample_item, response_text: "", self_rating: 4)
    explained = EnglishArcade::ExerciseGrader.grade(
      exercise,
      item: sample_item,
      response_text: "The consumer owns the smallest interface needed by its dependency.",
      self_rating: 3
    )

    assert_equal false, empty.fetch("correct")
    assert_equal 1, empty.fetch("rating")
    assert_equal true, explained.fetch("correct")
    assert_equal 3, explained.fetch("rating")
  end

  def test_cloze_ignores_unknown_keys_when_deciding_whether_an_answer_was_typed
    item = canonical_items.first
    exercise = factory.build(item, stage: :cloze)
    response = exercise.dig("payload", "blanks").to_h do |blank|
      expected = EnglishArcade::TextTools.words(item.fetch("best_answer"))[blank.fetch("start"), blank.fetch("length")].join(" ")
      blank["chips"] = [ expected ]
      [ blank.fetch("id"), expected ]
    end.merge("cheat" => "typed")

    grade = EnglishArcade::ExerciseGrader.grade(exercise, item: item, response: response)

    assert_equal true, grade.fetch("correct")
    assert_equal 3, grade.fetch("rating")
  end
end
