require "test_helper"

class ArcadeFlowTest < ActionDispatch::IntegrationTest
  setup do
    ArcadeExerciseEvent.delete_all
    ArcadeLesson.delete_all
    ArcadeStageState.delete_all
    @headers = { "REMOTE_USER" => "arena-flow-test", "ACCEPT" => "application/json" }
  end

  test "renders the isolated Arena hub and keeps the legacy launcher available" do
    get arena_path, headers: { "REMOTE_USER" => "arena-flow-test" }

    assert_response :success
    assert_select "html.arcade-document"
    assert_select "section.arena-hub"
    assert_select "nav.cockpit-nav", count: 0

    get english_arcade_path, headers: { "REMOTE_USER" => "arena-flow-test" }

    assert_response :success
    assert_select "a[href='#{arena_path}']"
  end

  test "HTML lesson creation redirects to a reload-safe lesson URL" do
    post arcade_lessons_path,
      params: { lesson: { target_mode: "mixed", size: 4, seed: "html-redirect" } },
      headers: { "REMOTE_USER" => "arena-flow-test" }

    lesson = ArcadeLesson.order(:id).last
    assert_redirected_to arcade_lesson_path(lesson)

    follow_redirect!(headers: { "REMOTE_USER" => "arena-flow-test" })
    assert_response :success
    assert_select "section.arena-lesson[data-controller='arcade-lesson']"
  end

  test "lesson shell exposes opt-in sound but no Arena Realtime controls" do
    post arcade_lessons_path,
      params: { lesson: { target_mode: "mixed", size: 1, seed: "sound-shell" } },
      headers: { "REMOTE_USER" => "arena-flow-test" }

    follow_redirect!(headers: { "REMOTE_USER" => "arena-flow-test" })
    assert_select "button[data-arcade-lesson-target='audioToggle'][aria-pressed='false']", text: "Sound off"
    assert_select "[data-arena-realtime]", count: 0
    assert_select "[data-english-arcade-voice-target]", count: 0
  end

  test "lesson shell follows the configured loopback companion port" do
    previous = ENV["ENGLISH_ARCADE_VOICE_COMPANION_PORT"]
    ENV["ENGLISH_ARCADE_VOICE_COMPANION_PORT"] = "43210"
    post arcade_lessons_path,
      params: { lesson: { target_mode: "mixed", size: 1, seed: "companion-port" } },
      headers: { "REMOTE_USER" => "arena-flow-test" }

    follow_redirect!(headers: { "REMOTE_USER" => "arena-flow-test" })
    assert_select "[data-arcade-lesson-companion-base-url-value='http://127.0.0.1:43210']"
  ensure
    previous.nil? ? ENV.delete("ENGLISH_ARCADE_VOICE_COMPANION_PORT") : ENV["ENGLISH_ARCADE_VOICE_COMPANION_PORT"] = previous
  end

  test "serves only the active answer-bearing payload and records idempotently without legacy writes" do
    legacy_counts = legacy_counts()

    post arcade_lessons_path(format: :json),
      params: { lesson: { target_mode: "single", target: "dsa", size: 4, seed: "contract-seed" } },
      headers: @headers,
      as: :json

    assert_response :created
    lesson_payload = JSON.parse(response.body).fetch("lesson")
    exercises = lesson_payload.fetch("exercises")
    current = exercises.fetch(0)
    future = exercises.fetch(1)
    assert_equal "meet", current.fetch("stage")
    assert current.dig("payload", "model_text").present?
    assert_equal %w[attempt_no boss card_key exercise_id position reason stage target type], future.keys.sort
    refute future.key?("payload")

    post arcade_lesson_results_path(lesson_id: lesson_payload.fetch("id")),
      params: { result: { exercise_id: current.fetch("exercise_id"), response: { confirmed: true }, response_ms: 1_000 } },
      headers: @headers,
      as: :json

    assert_response :created
    result = JSON.parse(response.body)
    assert_equal true, result.fetch("correct")
    assert result.dig("reveal", "best_answer").present?
    assert_equal 1, ArcadeExerciseEvent.count
    assert_equal legacy_counts, legacy_counts()

    post arcade_lesson_results_path(lesson_id: lesson_payload.fetch("id")),
      params: { result: { exercise_id: current.fetch("exercise_id"), response: { confirmed: true }, response_ms: 1_000 } },
      headers: @headers,
      as: :json

    assert_response :success
    assert_equal 1, ArcadeExerciseEvent.count
    assert_equal legacy_counts, legacy_counts()
  end

  test "rejects a future exercise and another learner's lesson" do
    post arcade_lessons_path(format: :json),
      params: { lesson: { target_mode: "single", target: "golang", size: 4, seed: "ownership-seed" } },
      headers: @headers,
      as: :json

    lesson_payload = JSON.parse(response.body).fetch("lesson")
    future = lesson_payload.fetch("exercises").fetch(1)

    post arcade_lesson_results_path(lesson_id: lesson_payload.fetch("id")),
      params: { result: { exercise_id: future.fetch("exercise_id"), response: "choice-1" } },
      headers: @headers,
      as: :json

    assert_response :unprocessable_entity
    assert_equal "invalid_exercise", JSON.parse(response.body).fetch("error")
    assert_equal 0, ArcadeExerciseEvent.count

    get arcade_lesson_path(lesson_payload.fetch("id"), format: :json),
      headers: @headers.merge("REMOTE_USER" => "someone-else")

    assert_response :not_found
  end

  test "a strong production unlocks transfer without requiring the optional speaking stage" do
    content = ArcadeContent.new
    item = content.items_for("dsa").find { |candidate| content.supported?(candidate, stage: "transfer", slot: 0) }
    exercise = content.build(item, stage: "produce")
    now = Time.current
    %w[cloze rebuild].each do |stage|
      ArcadeStageState.create!(
        learner_key: "arena-flow-test", target: item.fetch(:target), card_key: item.fetch(:key), stage: stage,
        status: "review", stability: 14, difficulty: 5, due_at: now + 1.day, reps: 1, streak: 1,
        last_result: true, last_reviewed_at: now, content_version: content.content_version(item)
      )
    end
    lesson = ArcadeLesson.create!(
      learner_key: "arena-flow-test", target_mode: "single", target: item.fetch(:target), targets: [ item.fetch(:target) ],
      status: "active", seed: "optional-speak", started_at: now, exercises_total: 1,
      plan: [ {
        "exercise_id" => exercise.fetch("exercise_id"), "factory_exercise_id" => exercise.fetch("exercise_id"),
        "card_key" => item.fetch(:key), "target" => item.fetch(:target), "stage" => "produce", "type" => "produce",
        "slot" => 0, "position" => 0, "reason" => "practice", "attempt_no" => 1, "boss" => false
      } ]
    )

    result = ArcadeLessonRecorder.new(learner_key: "arena-flow-test", content: content).call(
      lesson: lesson,
      result: { exercise_id: exercise.fetch("exercise_id"), response_text: item.fetch("best_answer"), self_rating: 4, response_ms: 4_000 }
    )

    assert_equal true, result.fetch("correct")
    assert_includes result.fetch("unlocked"), "speak"
    assert_includes result.fetch("unlocked"), "transfer"
    assert ArcadeStageState.exists?(learner_key: "arena-flow-test", card_key: item.fetch(:key), stage: "transfer")
  end

  private

  def legacy_counts
    {
      sessions: EnglishArcadeSession.count,
      cards: EnglishArcadeCard.count,
      attempts: EnglishArcadeAttempt.count
    }
  end
end
