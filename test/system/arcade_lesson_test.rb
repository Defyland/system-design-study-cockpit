require "application_system_test_case"

class ArcadeLessonTest < ApplicationSystemTestCase
  setup do
    ArcadeExerciseEvent.delete_all
    ArcadeLesson.delete_all
    ArcadeStageState.delete_all
    @learner_key = ENV["STUDY_COCKPIT_USERNAME"].presence || "anonymous"
  end

  test "a wrong recognition answer is explained and requeued in the same lesson" do
    visit "/arena"
    click_button "Start mixed lesson"

    assert_current_path %r{/arena/lessons/\d+}
    assert_selector "section.arena-lesson[data-controller='arcade-lesson']"
    assert_selector "[data-arcade-lesson-target='stage']", text: /meet/i

    click_button "Got it"
    click_button "Continue"
    assert_selector ".arena-choice", minimum: 2, wait: 5

    lesson = ArcadeLesson.order(:id).last
    entry = lesson.reload.plan.find { |candidate| candidate.fetch("position").to_i == lesson.summary.to_h.fetch("next_position", 0).to_i }
    item = ArcadeContent.new.item_by_key(entry.fetch("card_key"))
    exercise = ArcadeContent.new.build(item, stage: entry.fetch("stage"), slot: entry.fetch("slot", 0).to_i)
    wrong_option = exercise.fetch("payload").fetch("options").find { |option| option.fetch("text") != item.fetch(:best_answer) }

    find("[data-arena-choice='#{wrong_option.fetch("id")}']").click
    click_button "Confirm"

    assert_selector ".arena-feedback:not([hidden])", wait: 5
    assert_text "Not this time"
    assert_text "Model answer"
    assert_text(/Trap axis/i)
    assert_button "Try it again later"

    lesson.reload
    requeued = lesson.plan.find { |candidate| candidate.fetch("reason") == "relearn" }
    assert requeued, "a wrong answer should add one relearn entry"
    assert_equal 2, ArcadeExerciseEvent.where(arcade_lesson: lesson).count
    assert_equal "recognize", ArcadeExerciseEvent.where(arcade_lesson: lesson).order(:id).last.stage

    click_button "Try it again later"
    assert_selector ".arena-exercise", wait: 5
    assert_selector "[data-arcade-lesson-target='stage']", text: /meet|recognize|trap|cloze|rebuild|produce/i
    assert_equal 2, lesson.reload.summary.to_h.fetch("next_position").to_i
  end

  test "reload resumes the next position and a short lesson reaches results" do
    lesson = create_lesson(%w[meet meet])
    visit arcade_lesson_path(lesson)

    assert_selector "[data-arcade-lesson-target='position']", text: "1"
    assert_selector "[data-arcade-lesson-target='stage']", text: /meet/i
    click_button "Got it"
    assert_selector ".arena-feedback:not([hidden])", wait: 5
    click_button "Continue"

    assert_selector "[data-arcade-lesson-target='position']", text: "2", wait: 5
    page.driver.browser.navigate.refresh
    assert_selector "[data-arcade-lesson-target='position']", text: "2", wait: 5
    assert_selector "[data-arcade-lesson-target='stage']", text: /meet/i

    visit arena_path
    assert_selector "[data-arena-resume]", text: "1 of 2 exercises saved"
    assert_no_difference("ArcadeLesson.count") do
      click_link "Resume lesson"
      assert_current_path arcade_lesson_path(lesson), wait: 10
    end
    assert_selector "[data-arcade-lesson-target='position']", text: "2", wait: 5

    click_button "Got it"
    assert_selector ".arena-feedback:not([hidden])", wait: 5
    click_button "Continue"

    assert_selector ".arena-results:not([hidden])", wait: 5
    assert_text(/Lesson complete/i)
    assert_text "accuracy"
    assert_equal "finished", lesson.reload.status
    assert_equal 2, ArcadeExerciseEvent.where(arcade_lesson: lesson).count
  end

  test "a new exercise clears the previous reference and starts its own response timer" do
    lesson = create_lesson(%w[meet meet])
    visit arcade_lesson_path(lesson)
    assert_selector "[data-arcade-lesson-target='position']", text: "1"
    click_button "Got it"
    assert_selector ".arena-feedback:not([hidden])"
    assert_selector "[data-arcade-lesson-target='exercise'][inert]"

    find("[data-action='arcade-lesson#openDossier']").click
    assert_selector "dialog[open]", text: "Model answer:"
    find("[data-action='arcade-lesson#closeDossier']").click

    # Simulate a long feedback-reading break without sleeping in the test.
    page.execute_script(<<~JS)
      window.arenaTestClockOffset = 60000;
      const originalNow = performance.now.bind(performance);
      performance.now = () => originalNow() + window.arenaTestClockOffset;
    JS
    click_button "Continue"
    assert_selector "[data-arcade-lesson-target='position']", text: "2"
    assert_no_selector "[data-arcade-lesson-target='exercise'][inert]"
    find("[data-action='arcade-lesson#openDossier']").click
    assert_selector "dialog[open]", text: "Answer this exercise"
    assert_no_selector "dialog[open]", text: "Model answer:"
    find("[data-action='arcade-lesson#closeDossier']").click

    page.execute_script("window.arenaTestClockOffset = 62000")
    click_button "Got it"
    assert_selector ".arena-feedback:not([hidden])"
    event = lesson.arcade_exercise_events.order(:position).last
    assert_operator event.response_ms, :>=, 2000
    assert_operator event.response_ms, :<, 15000
  end

  private

  def create_lesson(stages)
    content = ArcadeContent.new
    items = content.items_for("dsa").first(stages.length)
    entries = stages.each_with_index.map do |stage, index|
      item = items.fetch(index)
      exercise = content.build(item, stage: stage, slot: 0)
      {
        "exercise_id" => exercise.fetch("exercise_id"),
        "factory_exercise_id" => exercise.fetch("exercise_id"),
        "card_key" => item.fetch(:key),
        "target" => item.fetch(:target),
        "stage" => stage,
        "type" => exercise.fetch("type"),
        "slot" => 0,
        "position" => index,
        "reason" => "practice",
        "attempt_no" => 1,
        "boss" => false
      }
    end

    ArcadeLesson.create!(
      learner_key: @learner_key,
      target_mode: "single",
      target: "dsa",
      targets: [ "dsa" ],
      status: "active",
      seed: "system-lesson",
      started_at: Time.current,
      exercises_total: entries.length,
      plan: entries
    )
  end
end
