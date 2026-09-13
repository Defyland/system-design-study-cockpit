# frozen_string_literal: true

require "test_helper"

class ArcadeResumeInterviewContentTest < ActiveSupport::TestCase
  setup do
    ArcadeExerciseEvent.delete_all
    ArcadeLesson.delete_all
    ArcadeStageState.delete_all
    @now = Time.utc(2026, 9, 7, 18)
  end

  test "role cards are isolated from canonical career IDs and preserve their role" do
    content = ArcadeContent.new
    canonical_ids = content.items_for("career").map { |item| item.fetch("id") }
    interview_ids = content.items_for("interview").map { |item| item.fetch("id") }

    assert_equal 12, interview_ids.length
    assert_equal interview_ids.length, interview_ids.uniq.length
    assert_empty interview_ids & canonical_ids

    EnglishArcadeResumeInterviewProfile.interview_roles.each do |role|
      cards = content.items_for("interview", interview_role: role)
      assert_equal 3, cards.length
      assert_equal [ role ], cards.map { |item| item.fetch("interview_role") }.uniq
      assert cards.all? { |item| item.fetch("content_version") == EnglishArcadeResumeInterviewProfile::ROLE_CONTENT_VERSION }
    end
  end

  test "role metadata keeps the interview selector labels and focus in one profile contract" do
    assert_equal %w[frontend backend fullstack smarttv], EnglishArcadeResumeInterviewProfile.interview_roles
    assert_equal "Full-stack", EnglishArcadeResumeInterviewProfile.role_metadata("fullstack").fetch(:label)
    assert_equal "End-to-end decisions and product context", EnglishArcadeResumeInterviewProfile.role_metadata("fullstack").fetch(:focus)
    assert_equal EnglishArcadeResumeInterviewProfile::ROLE_METADATA, EnglishArcadeResumeInterviewProfile.role_metadata
  end

  test "reordering authored definitions preserves each role card identity content and checks" do
    source_cards = ArcadeContent.new.builder.cards_for("career")
    baseline = EnglishArcadeResumeInterviewProfile.role_cards(source_cards, role: "frontend").index_by { |item| item.fetch(:key) }
    reordered_decks = EnglishArcadeResumeInterviewProfile::ROLE_DECKS.merge(
      "frontend" => EnglishArcadeResumeInterviewProfile::ROLE_DECKS.fetch("frontend").reverse
    )
    reordered = EnglishArcadeResumeInterviewProfile.role_cards(source_cards, role: "frontend", decks: reordered_decks).index_by { |item| item.fetch(:key) }

    assert_equal baseline.keys.sort, reordered.keys.sort
    baseline.each do |id, item|
      candidate = reordered.fetch(id)
      assert_equal item.fetch(:answer_text), candidate.fetch(:answer_text)
      assert_equal item.fetch(:recall_check), candidate.fetch(:recall_check)
      assert_equal item.dig(:variants, "follow_up"), candidate.dig(:variants, "follow_up")
      assert_equal item.dig(:variants, "delayed_variant"), candidate.dig(:variants, "delayed_variant")
    end
  end

  test "each role has authored changed-question transfer variants without resume boilerplate" do
    content = ArcadeContent.new

    EnglishArcadeResumeInterviewProfile.interview_roles.each do |role|
      content.items_for("interview", interview_role: role).each do |item|
        assert content.supported?(item, stage: "transfer", slot: 0)
        assert content.supported?(item, stage: "transfer", slot: 1)

        [ item.fetch("best_answer"), item.dig("follow_up", "best_answer"), item.dig("delayed_variant", "best_answer") ].each do |spoken_answer|
          refute_match(/my resume documents|the resume confirms/i, spoken_answer)
        end
      end
    end
  end

  test "active interview meet exposes learning while produce and transfer remain answer-safe" do
    content = ArcadeContent.new
    item = content.items_for("interview", interview_role: "fullstack").first

    meet = content.learner_exercise(item, stage: "meet", include_model: true)
    produce = content.learner_exercise(item, stage: "produce")
    transfer = content.learner_exercise(item, stage: "transfer", slot: 0)

    assert_equal %w[answer_structure answer_versions pt_help reasoning_questions useful_phrases], meet.dig("payload", "learning").keys.sort
    assert_equal %w[deep medium short], meet.dig("payload", "learning", "answer_versions").keys.sort
    refute produce.dig("payload", "learning")
    refute transfer.dig("payload", "learning")
  end

  test "every role card teaches a first person decision path only during study and reveal" do
    content = ArcadeContent.new
    content.items_for("interview").each do |item|
      questions = item.dig("learning", "reasoning_questions")
      assert_equal 4, questions.length, item.fetch("id")
      questions.each do |entry|
        assert entry.fetch("question").end_with?("?"), item.fetch("id")
        assert_match(/\bI(?:\b|[’'])/, entry.fetch("answer"), item.fetch("id"))
        assert_operator entry.fetch("answer").split.length, :>=, 20
      end

      exercise = content.build(item, stage: "produce")
      reveal = content.reveal(item, exercise: exercise)
      assert_equal questions, reveal.dig("learning", "reasoning_questions")
      %w[produce transfer].each do |stage|
        payload = content.learner_exercise(item, stage: stage).to_json
        questions.each { |entry| refute_includes payload, entry.fetch("answer") }
      end
    end
  end

  test "each role card accepts its authored medium and short recall answers with an honest assessment label" do
    content = ArcadeContent.new

    EnglishArcadeResumeInterviewProfile.interview_roles.each do |role|
      content.items_for("interview", interview_role: role).each do |item|
        exercise = content.build(item, stage: "produce")
        versions = item.dig("learning", "answer_versions")

        [ versions.fetch("medium"), versions.fetch("short") ].each do |answer|
          grade = EnglishArcade::ExerciseGrader.grade(exercise, item: item, response_text: answer, self_rating: 4)
          assert_equal "phrase_recall", grade.dig("details", "assessment_kind")
          assert_equal true, grade.fetch("correct")
          assert_operator grade.fetch("rating"), :<=, 3
        end
      end
    end
  end

  test "each role creates, reloads, and grades its isolated meet produce transfer rehearsal" do
    EnglishArcadeResumeInterviewProfile.interview_roles.each do |role|
      learner_key = "resume-role-#{role}"
      composer = ArcadeLessonComposer.new(learner_key: learner_key, clock: -> { @now })
      lesson = composer.call(target_mode: "interview", interview_role: role, size: 3, new_cards: 1, seed: "role-#{role}")

      assert_equal %w[meet produce transfer], lesson.plan.map { |entry| entry.fetch("stage") }
      plan_items = lesson.plan.map { |entry| ArcadeContent.new.item_by_key(entry.fetch("card_key")) }
      assert_equal [ role ], plan_items.map { |item| item.fetch("interview_role") }.uniq
      assert lesson.plan.none? { |entry| entry.key?("interview_role") }
      assert_equal 1, lesson.plan.map { |entry| entry.fetch("card_key") }.uniq.length

      reloaded = ArcadeLesson.find(lesson.id)
      exercises = composer.exercises_for(reloaded, current_position: 0)
      item = ArcadeContent.new.item_by_key(reloaded.plan.first.fetch("card_key"))
      recorder = ArcadeLessonRecorder.new(learner_key: learner_key, clock: -> { @now })

      meet = exercises.fetch(0)
      result = recorder.call(lesson: reloaded, result: { exercise_id: meet.fetch("exercise_id"), response: { confirmed: true }, response_ms: 100 })
      assert_equal item.fetch("id"), ArcadeLesson.find(lesson.id).arcade_exercise_events.last.card_key
      assert result.dig("reveal", "learning").present?

      produce = composer.exercises_for(ArcadeLesson.find(lesson.id), current_position: 1).fetch(1)
      recorder.call(lesson: lesson, result: { exercise_id: produce.fetch("exercise_id"), response_text: item.fetch("best_answer"), self_rating: 4, response_ms: 100 })

      transfer = composer.exercises_for(ArcadeLesson.find(lesson.id), current_position: 2).fetch(2)
      option = transfer.dig("payload", "options").find { |candidate| candidate.fetch("text") == item.dig("follow_up", "best_answer") }
      recorder.call(lesson: lesson, result: { exercise_id: transfer.fetch("exercise_id"), response: option.fetch("id"), response_ms: 100 })

      assert_equal item.fetch("id"), ArcadeLesson.find(lesson.id).arcade_exercise_events.order(:position).last.card_key
    end
  end

  test "a reviewed role deck stays in produce and delayed transfer rehearsal" do
    content = ArcadeContent.new
    learner_key = "reviewed-resume-role"
    cards = content.items_for("interview", interview_role: "frontend")

    cards.each_with_index do |item, index|
      ArcadeStageState.create!(
        learner_key: learner_key,
        target: item.fetch(:target),
        card_key: item.fetch(:key),
        stage: "produce",
        status: "review",
        stability: 4,
        difficulty: 5,
        due_at: @now + 1.day,
        reps: 2,
        streak: 2,
        last_result: true,
        last_reviewed_at: @now - (index + 1).days,
        content_version: content.content_version(item)
      )
      ArcadeStageState.create!(
        learner_key: learner_key,
        target: item.fetch(:target),
        card_key: item.fetch(:key),
        stage: "transfer",
        status: "review",
        stability: 4,
        difficulty: 5,
        due_at: index.zero? ? @now - 1.minute : @now + 1.day,
        reps: 2,
        streak: 2,
        last_result: true,
        last_reviewed_at: @now - (index + 1).days,
        content_version: content.content_version(item)
      )
    end

    lesson = ArcadeLessonComposer.new(learner_key: learner_key, content: content, clock: -> { @now }).call(
      target_mode: "interview", interview_role: "frontend", size: 4, new_cards: 2, seed: "reviewed-role"
    )

    assert_equal %w[produce transfer produce transfer], lesson.plan.map { |entry| entry.fetch("stage") }
    assert_equal %w[due due practice practice], lesson.plan.map { |entry| entry.fetch("reason") }
    assert_equal [ cards.first.fetch(:key), cards.last.fetch(:key) ], lesson.plan.each_slice(2).map { |pair| pair.first.fetch("card_key") }
    assert_equal [ 1, 1 ], lesson.plan.select { |entry| entry.fetch("stage") == "transfer" }.map { |entry| entry.fetch("slot") }
    assert_equal lesson.plan.length, lesson.plan.map { |entry| [ entry.fetch("card_key"), entry.fetch("stage") ] }.uniq.length
    assert_empty lesson.plan.select { |entry| entry.fetch("boss") }

    ArcadeStageState.where(learner_key: learner_key).update_all(due_at: @now + 1.day)
    practice = ArcadeLessonComposer.new(learner_key: learner_key, content: content, clock: -> { @now }).call(
      target_mode: "interview", interview_role: "frontend", size: 2, new_cards: 0, seed: "reviewed-role-practice"
    )

    assert_equal [ cards.last.fetch(:key) ], practice.plan.map { |entry| entry.fetch("card_key") }.uniq
    assert_equal %w[produce transfer], practice.plan.map { |entry| entry.fetch("stage") }
    assert_equal [ "practice" ], practice.plan.map { |entry| entry.fetch("reason") }.uniq
  end

  test "a due role answer precedes unseen interview cards without duplicate entries" do
    content = ArcadeContent.new
    learner_key = "due-before-fresh-role"
    due_item = content.items_for("interview", interview_role: "backend").first
    ArcadeStageState.create!(
      learner_key: learner_key, target: due_item.fetch(:target), card_key: due_item.fetch(:key),
      stage: "produce", status: "review", stability: 4, difficulty: 5, due_at: @now - 1.minute,
      reps: 2, streak: 2, last_result: true, last_reviewed_at: @now - 2.days,
      content_version: content.content_version(due_item)
    )
    ArcadeStageState.create!(
      learner_key: learner_key, target: due_item.fetch(:target), card_key: due_item.fetch(:key),
      stage: "transfer", status: "review", stability: 4, difficulty: 5, due_at: @now + 1.day,
      reps: 2, streak: 2, last_result: true, last_reviewed_at: @now - 2.days,
      content_version: content.content_version(due_item)
    )

    lesson = ArcadeLessonComposer.new(learner_key: learner_key, content: content, clock: -> { @now }).call(
      target_mode: "interview", interview_role: "backend", size: 3, new_cards: 2, seed: "due-before-fresh"
    )

    assert_equal [ due_item.fetch(:key), due_item.fetch(:key) ], lesson.plan.first(2).map { |entry| entry.fetch("card_key") }
    assert_equal %w[produce transfer], lesson.plan.first(2).map { |entry| entry.fetch("stage") }
    assert_equal %w[due due], lesson.plan.first(2).map { |entry| entry.fetch("reason") }
    assert_operator lesson.plan.length, :<=, 3
    assert_equal lesson.plan.length, lesson.plan.map { |entry| entry.fetch("exercise_id") }.uniq.length
  end
end
