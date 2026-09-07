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

  def test_resume_recall_accepts_authored_alternatives_without_demanding_verbatim_wording
    item = resume_item.except("interview_role")
    exercise = factory.build(item, stage: :produce)
    [ item.fetch("best_answer"), "At Bornlogic, I split the frontend into independently released apps. Our release time fell from two days to less than an hour." ].each do |answer|
      grade = EnglishArcade::ExerciseGrader.grade(exercise, item: item, response_text: answer, self_rating: 4)
      assert_equal true, grade.fetch("correct")
      assert_equal 3, grade.fetch("rating")
      assert_equal "phrase_recall", grade.dig("details", "assessment_kind")
    end
  end

  def test_resume_recall_rejects_fragments_unrelated_answers_and_missing_self_rating
    item = resume_item
    exercise = factory.build(item, stage: :produce)
    [ "", "microfrontends release time", "I have worked with many interesting teams and I enjoy finding new ways to solve difficult problems together." ].each do |answer|
      grade = EnglishArcade::ExerciseGrader.grade(exercise, item: item, response_text: answer, self_rating: 4)
      assert_equal false, grade.fetch("correct")
    end
    grade = EnglishArcade::ExerciseGrader.grade(exercise, item: item, response_text: item.fetch("best_answer"))
    assert_equal false, grade.fetch("correct")
  end

  def test_resume_recall_never_claims_to_validate_the_meaning_of_matching_phrases
    item = resume_item
    exercise = factory.build(item, stage: :produce)
    grade = EnglishArcade::ExerciseGrader.grade(
      exercise, item: item, self_rating: 4,
      response_text: "I did not work on microfrontends and I did not reduce release time at all in this project."
    )
    # Phrase matching cannot determine whether the learner's claims are true.
    assert_equal "phrase_recall", grade.dig("details", "assessment_kind")
    assert_equal %w[meaning grammar fluency pronunciation], grade.dig("details", "unassessed")
    assert_operator grade.fetch("rating"), :<=, 3
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

  private

  def resume_item
    sample_item.merge(
      "id" => "resume-frontend-test",
      "interview_role" => "frontend",
      "best_answer" => "At Bornlogic, I led the move to microfrontends across five squads and reduced release time from two days to under an hour.",
      "recall_check" => {
        "minimum_words" => 15, "required_groups" => 2,
        "key_points" => [ [ "microfrontends", "independently released apps" ], [ "release time", "deployment time" ] ]
      }
    )
  end
end
