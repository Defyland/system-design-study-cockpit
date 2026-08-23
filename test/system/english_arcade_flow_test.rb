require "application_system_test_case"
require_relative "../english_arcade/english_arcade_fixture_validator"

class EnglishArcadeFlowTest < ApplicationSystemTestCase
  setup do
    EnglishArcadeAttempt.delete_all
    EnglishArcadeCard.delete_all
    EnglishArcadeSession.delete_all
    CheckpointAttempt.delete_all
    ReviewSchedule.delete_all
    Reminder.delete_all
    MisconceptionEvent.delete_all
    LearningRecord.delete_all
    Checkpoint.delete_all
    StudyBlock.delete_all
    StudyProgress.delete_all
    StudyDocument.delete_all
    @fixture = EnglishArcade::FixtureValidator.load_fixture
    @item = @fixture.fetch("targets").first.fetch("items").first
  end

  test "learner selects a target, completes recall and Feynman, then reattempts an error" do
    visit "/english-arcade"

    assert_selector "section.english-arcade[data-controller='english-arcade']"
    assert_selector "h1", text: /English C2 Arcade/i
    assert_selector "form[action*='english-arcade'] [role='radiogroup'][aria-label='Interview target']"
    assert_link "Export 30-day progress JSON"
    assert_selector "details.arcade-progress"
    find("label[for='english-arcade-target-dsa']").click
    assert_selector "input#english-arcade-target-dsa:checked", visible: :all
    click_button "Start closed-book session"

    assert_selector ".arcade-kicker", text: /closed-book question/i
    assert_selector "form[data-english-arcade-target='form']"
    assert_no_selector ".arcade-answer"

    # The fixture adapter rotates choices, so the second visible option is a
    # deterministic wrong answer without reading a server-side answer key.
    all("label.arcade-choice")[1].click
    click_button "Commit answer"

    assert_selector "#feynman-title", text: /Feynman pass before the reveal/i
    fill_in "Say or write the reasoning", with: "The invariant explains why the retained window remains valid."
    click_button "Reveal feedback"

    assert_text "Black Box: the miss is evidence"
    assert_text "Answer after attempt"
    assert_selector ".arcade-answer"

    assert_selector "label[for='english-arcade-black-box-root-cause']"
    assert_selector "label[for='english-arcade-black-box-missing-signal']"
    assert_selector "label[for='english-arcade-black-box-preventive-rule']"
    assert_selector "label[for='english-arcade-black-box-targeted-exercise']"
    assert_selector "label[for='english-arcade-black-box-retest-dates']"
    fill_in "Actionable root cause", with: "I skipped the boundary condition before moving the left edge."
    fill_in "Missing mental model / signal", with: "The invariant should signal when the retained window becomes invalid."
    fill_in "Preventive rule", with: "State the boundary condition before changing either pointer."
    fill_in "Targeted exercise", with: "Re-solve one sliding-window variant and narrate the invariant."
    fill_in "Retest dates", with: "Retry tomorrow, then review again in seven days."
    click_button "Save post-mortem"

    assert_text "box 1"
    click_link "Retry this question"
    assert_selector ".arcade-kicker", text: /retry/i
    assert_text "DSA & algorithms"
  end

  test "target choice survives a reload and drives the next item" do
    visit "/english-arcade"
    find("label[for='english-arcade-target-golang']").click
    assert_selector "input#english-arcade-target-golang:checked", visible: :all
    click_button "Start closed-book session"

    assert_selector ".arcade-question h2", text: /Golang/i
    page.driver.browser.navigate.refresh

    assert_selector "input[name='english_arcade_session[target]'][value='golang']:checked", visible: :all
    assert_text "Golang"
    assert_selector "input[name='english_arcade_session[target]'][value='golang']"
  end
end
