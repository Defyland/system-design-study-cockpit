require "application_system_test_case"

class ArcadeInterviewLearningTest < ApplicationSystemTestCase
  setup do
    ArcadeExerciseEvent.delete_all
    ArcadeLesson.delete_all
    ArcadeStageState.delete_all
  end

  test "a frontend interview teaches useful English then asks for recall without the model" do
    visit arena_path
    choose "arena-interview-role-frontend"
    click_button "Interview mode"

    assert_selector "[data-arcade-lesson-target='stage']", text: /meet/i
    assert_selector ".arena-model-card"
    assert_text "Build the answer"
    assert_text "Useful English"
    find(".arena-pt-help summary", text: "Ajuda em português").click
    assert_selector ".arena-pt-help[open] [lang='pt-BR']"
    lesson = ArcadeLesson.order(:id).last
    assert lesson.plan.all? { |entry| entry.fetch("card_key").start_with?("resume-frontend-") }
    item = ArcadeContent.new.item_by_key(lesson.plan.first.fetch("card_key"))

    click_button "Got it"
    assert_selector ".arena-feedback:not([hidden])"
    click_button "Continue"

    assert_selector "[data-arcade-lesson-target='stage']", text: /produce/i
    assert_no_selector ".arena-model-card"
    assert_no_selector ".arena-learning-card"
    find("[data-action='arcade-lesson#openDossier']").click
    assert_no_selector "dialog[open]", text: "Model answer:"
    find("[data-action='arcade-lesson#closeDossier']").click
    fill_in "Your answer", with: item.fetch("best_answer")
    select "4 · easy", from: "arena-self-rating"
    click_button "Submit production"

    assert_selector ".arena-feedback:not([hidden])", text: "Recall recorded"
    assert_text "Automatic phrase recall"
    assert_text "Meaning, grammar, fluency, and pronunciation are not assessed"
    assert_selector "[data-arena-production-diff]"
    assert_text "Resume facts used in this answer"
    click_button "Continue"

    assert_selector "[data-arcade-lesson-target='stage']", text: /transfer/i
    assert_text item.dig("follow_up", "prompt")
    assert_no_selector ".arena-learning-card"
  end
end
