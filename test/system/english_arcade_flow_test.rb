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

    # Select an authored distractor by its learner-visible text. Choice order
    # is opaque and may rotate, so position is not a valid test contract.
    assert_selector "label.arcade-choice", text: /Obviously it is a sliding window/i
    find("label.arcade-choice", text: /Obviously it is a sliding window/i).click
    fill_in "Typed answer", with: "I would state the invariant, explain the trade-off, and verify the boundary with a counterexample before writing implementation details."
    fill_critical_ledger
    select "English directly", from: "english_arcade_attempt_english_directness"
    %w[clarity precision naturalness pragmatic_appropriateness technical_correctness].each do |axis|
      select "3", from: "english_arcade_attempt_self_#{axis}"
    end
    click_button "Commit answer"

    assert_selector "#feynman-title", text: /Feynman pass before the reveal/i
    fill_in "Write the reasoning", with: "The invariant explains why the retained window remains valid, and I would trace a duplicate boundary before deciding the loop is correct."
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
    # Retry is the delayed_variant contract; age the persisted parent in this
    # system fixture instead of weakening the server-side seven-day boundary.
    EnglishArcadeAttempt.order(:id).last.update!(answered_at: 8.days.ago)
    click_button "Retry this question"
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

  test "guided study reveals authored coaching and keeps navigation non-assessing" do
    visit "/english-arcade"
    find("label[for='english-arcade-target-career']").click
    click_button "Start guided study"

    assert_selector ".guided-experience"
    assert_selector ".guided-board"
    assert_selector ".guided-card", count: 5, visible: :all
    assert_text(/My answer to practise aloud/i)
    assert_text(/Medium · canonical/i)
    assert_text(/Critical-thinking path/i)
    assert_text(/Sources, provenance, and confidentiality boundary/i)
    assert_no_selector ".arcade-question"
    assert_no_selector "form[action*='english-arcade/attempts']"
    assert_no_text "Commit answer"

    click_button "Ready"
    assert_text "Ready saved locally for this card."
    click_button "Next card"
    assert_text "Card 2 of 5"
    assert_equal 0, EnglishArcadeAttempt.count
  end

  private

  def fill_critical_ledger
    {
      "#english-arcade-problem-frame" => "The interviewer needs a bounded decision for the stated input and workload.",
      "#english-arcade-evidence-verified" => "The authored prompt establishes the input boundary.",
      "#english-arcade-evidence-inference" => "The invariant follows from that boundary.",
      "#english-arcade-evidence-assumption" => "The workload remains within the stated operational limit.",
      "#english-arcade-evidence-gap" => "Production scale still needs measurement.",
      "#english-arcade-source-quality" => "The authored prompt is primary; runtime evidence is still pending.",
      "#english-arcade-counterexample" => "An adversarial duplicate can invalidate the assumed bound.",
      "#english-arcade-change-my-mind" => "A measured trace that breaks the bound would change my recommendation."
    }.each { |selector, value| find(selector).set(value) }
    find("#english-arcade-confidence-percent").set("70")
    find("summary", text: /Real trade-off branch/).click
    {
      "#english-arcade-comparison-option-a" => "Keep the simple implementation.",
      "#english-arcade-comparison-option-b" => "Use indexed state.",
      "#english-arcade-comparison-tradeoff" => "Memory buys fewer scans.",
      "#english-arcade-comparison-switch-condition" => "Switch when measured load crosses the bound."
    }.each { |selector, value| find(selector).set(value) }
    find("summary", text: /False-equivalence branch/).click
    {
      "#english-arcade-comparison-rejected-alternative" => "The alternative violates the same input contract.",
      "#english-arcade-comparison-hard-constraint" => "The input contract is fixed.",
      "#english-arcade-comparison-decision-rule" => "Clarify the contract before comparing."
    }.each { |selector, value| find(selector).set(value) }
  end
end
