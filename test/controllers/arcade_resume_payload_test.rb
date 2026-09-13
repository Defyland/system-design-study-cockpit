require "test_helper"

class ArcadeResumePayloadTest < ActionDispatch::IntegrationTest
  test "historical resume plans are rejected instead of resolving to canonical career content" do
    # Persisted shape from b88bd6c/6e4895a, before role IDs were isolated.
    factory_id = "career-01-a-60-to-90-second-introduction:meet:0:4d692781"
    lesson = ArcadeLesson.create!(
      learner_key: "legacy-resume", target_mode: "interview", target: "interview",
      targets: [ "career" ], status: :active, seed: "historical-resume",
      started_at: Time.current, exercises_total: 1,
      plan: [ { "exercise_id" => factory_id, "factory_exercise_id" => factory_id,
        "card_key" => "career-01-a-60-to-90-second-introduction", "target" => "career",
        "stage" => "meet", "slot" => 0, "position" => 0, "attempt_no" => 1,
        "reason" => "new", "boss" => false } ]
    )
    headers = { "REMOTE_USER" => "legacy-resume" }
    get arcade_lesson_path(lesson, format: :json), headers: headers
    assert_response :unprocessable_entity
    assert_equal "stale_content", response.parsed_body.fetch("error")

    get arcade_lesson_path(lesson), headers: headers
    assert_response :unprocessable_entity
    assert_select "h1", "This lesson's study material has changed."
    assert_select "a[href=?]", arena_path, text: "Return to Arena"

    assert_no_difference "ArcadeExerciseEvent.count" do
      post arcade_lesson_results_path(lesson_id: lesson.id, format: :json),
        params: { result: { exercise_id: factory_id, response: { confirmed: true }, response_ms: 100 } },
        headers: headers, as: :json
    end
    assert_response :unprocessable_entity
    assert_equal "stale_content", response.parsed_body.fetch("error")
  end

  test "each role serves only the active allowed material and refuses future submissions" do
    EnglishArcadeResumeInterviewProfile.interview_roles.each do |role|
      headers = { "REMOTE_USER" => "payload-#{role}" }
      post arcade_lessons_path(format: :json),
        params: { lesson: { target_mode: "interview", interview_role: role, size: 6, new_cards: 2 } },
        headers: headers, as: :json
      assert_response :created
      lesson = ArcadeLesson.find(response.parsed_body.dig("lesson", "id"))
      exercises = response.parsed_body.dig("lesson", "exercises")
      content = ArcadeContent.new
      current = content.item_by_key(lesson.plan.first.fetch("card_key"))
      future = content.item_by_key(lesson.plan.fetch(3).fetch("card_key"))
      assert_equal current.fetch("best_answer"), exercises.first.dig("payload", "model_text")
      exercises.drop(1).each { |exercise| refute exercise.key?("payload") }
      serialized = response.parsed_body.to_json
      [ future.fetch("prompt"), future.fetch("best_answer"), future.dig("follow_up", "best_answer"), future.dig("delayed_variant", "best_answer") ].each do |text|
        refute_includes serialized, text.to_json
      end
      future.dig("learning", "reasoning_questions").each do |entry|
        refute_includes serialized, entry.fetch("answer").to_json
      end
      refute_includes serialized, "recall_check"

      assert_no_difference "ArcadeExerciseEvent.count" do
        post arcade_lesson_results_path(lesson_id: lesson.id, format: :json),
          params: { result: { exercise_id: exercises.fetch(1).fetch("exercise_id"), response_text: "A premature answer", response_ms: 100, self_rating: 4 } },
          headers: headers, as: :json
      end
      assert_response :unprocessable_entity

      post arcade_lesson_results_path(lesson_id: lesson.id, format: :json),
        params: { result: { exercise_id: exercises.first.fetch("exercise_id"), response: { confirmed: true }, response_ms: 100 } },
        headers: headers, as: :json
      assert_response :success
      get arcade_lesson_path(lesson, format: :json), headers: headers
      assert_response :success
      assert_equal 1, response.parsed_body.dig("lesson", "resume_position")
      serialized = response.parsed_body.to_json
      [ current.fetch("best_answer"), current.dig("learning", "answer_versions", "short"), future.fetch("best_answer") ].each do |text|
        refute_includes serialized, text.to_json
      end
      refute_includes serialized, "recall_check"
      refute_includes serialized, "answer_structure"
      refute_includes serialized, "reasoning_questions"
    end
  end
end
