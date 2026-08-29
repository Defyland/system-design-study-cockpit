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
    assert_selector "h1", text: /English\s+Arcade/i
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

    assert_selector "section.arcade-feedback.wrong[aria-live='assertive']", wait: 5
    assert_no_selector "#feynman-title", wait: 5
    assert_text "Black Box: the miss is evidence", wait: 5
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
    assert_button "Retry this question", wait: 5

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
    assert_selector "input[name='english_arcade_session[target]'][value='golang']", visible: :all
  end

  test "guided study reveals authored coaching and keeps navigation non-assessing" do
    visit "/english-arcade"
    find("label[for='english-arcade-target-career']").click
    click_button "Play falling cards"

    assert_selector ".guided-experience"
    assert_selector ".guided-board"
    assert_selector ".guided-card", count: 5, visible: :all
    assert_equal [ 4 ] * 5, page.evaluate_script("Array.from(document.querySelectorAll('.guided-card')).map((card) => card.querySelectorAll('[data-guided-game-options=best_answer] [data-guided-game-option]').length)")
    assert_text(/Best answer · practise in first person/i)
    assert_text(/Canonical response/i)
    assert_text(/Critical-thinking path/i)
    assert_text(/Sources and evidence boundary/i)
    assert_button "Start round"
    assert_no_selector ".arcade-question"
    assert_no_selector "form[action*='english-arcade/attempts']"
    assert_no_text "Commit answer"

    within ".guided-card:not([hidden])" do
      click_button "Start round"
      assert_selector "[data-guided-game-option]:not([hidden])", count: 4, visible: :all
      correct_index = find("[data-guided-game-options='best_answer'] [data-guided-game-correct='true']", visible: :all)["data-guided-game-index"]
      page.execute_script("window.dispatchEvent(new KeyboardEvent('keydown', { key: '#{correct_index.to_i + 1}', bubbles: true }))")
      assert_text "Correct phrase"
      click_button "Complete the sentence"
      assert_text(/Complete with the exact authored phrase/i)
      click_button "Start round"
      assert_selector "[data-guided-game-options='completion'] [data-guided-game-option]:not([hidden])", count: 4, visible: :all
    end

    click_button "Ready"
    assert_text "Ready saved locally for this card."
    click_button "Next card"
    assert_text "Card 2 of 5"
    assert_equal 0, EnglishArcadeAttempt.count
  end

  test "guided game resolves outcomes, accelerates the next card, and preserves score" do
    visit "/english-arcade"
    find("label[for='english-arcade-target-career']").click
    click_button "Play falling cards"

    click_button "Start round"
    assert_selector ".guided-game-stage[data-game-state='running']"
    assert_selector "[data-guided-game-options='best_answer'] [data-guided-game-option]:not([hidden])", count: 4, visible: :all

    first_round = page.evaluate_script(<<~JAVASCRIPT)
      (() => {
        const stage = document.querySelector('.guided-card:not([hidden]) [data-guided-game-stage]')
        const option = stage.querySelector("[data-guided-game-options='best_answer'] [data-guided-game-option]")
        return {
          deadline: Number(stage.dataset.gameDeadlineMs),
          duration: Number.parseFloat(option.style.getPropertyValue('--duration')),
          state: stage.dataset.gameState
        }
      })()
    JAVASCRIPT
    assert_equal "running", first_round.fetch("state")
    assert_operator first_round.fetch("deadline"), :>, 0
    assert_operator first_round.fetch("duration"), :>, 0
    assert_text "Score 0"
    assert_text "Streak 0"
    assert_text "Level 1"
    assert_text(/Speed 1\.0/i)
    assert_text(/Deadline .*seconds/i)

    page.execute_script(<<~JAVASCRIPT)
      (() => {
        const root = document.querySelector("section.english-arcade[data-controller='english-arcade']")
        const controller = window.Stimulus.getControllerForElementAndIdentifier(root, 'english-arcade')
        const game = document.querySelector('.guided-card:not([hidden]) [data-guided-game-card]')
        controller.finishGuidedGameChoice(game.querySelector("[data-guided-game-options='best_answer'] [data-guided-game-correct='true']"))
      })()
    JAVASCRIPT
    assert_selector ".guided-game-stage[data-game-state='correct']"
    assert_text "Correct phrase"
    assert_text "Score 100"
    assert_text "Streak 1"
    assert_text "Level 2"

    # Navigation and mode changes are explicit while a round is running; they
    # must not silently discard a live deadline or its falling cards.
    click_button "Next round"
    assert_text "Card 2 of 5"
    assert_selector ".guided-game-stage[data-game-state='running']"
    second_round = page.evaluate_script(<<~JAVASCRIPT)
      (() => {
        const stage = document.querySelector('.guided-card:not([hidden]) [data-guided-game-stage]')
        const option = stage.querySelector("[data-guided-game-options='best_answer'] [data-guided-game-option]")
        return {
          deadline: Number(stage.dataset.gameDeadlineMs),
          duration: Number.parseFloat(option.style.getPropertyValue('--duration')),
          score: document.querySelector('.guided-card:not([hidden]) [data-guided-game-score]').textContent
        }
      })()
    JAVASCRIPT
    assert_operator second_round.fetch("duration"), :<, first_round.fetch("duration")
    assert_operator second_round.fetch("deadline"), :<, first_round.fetch("deadline")
    assert_includes second_round.fetch("score"), "Score 100"

    click_button "Complete the sentence"
    assert_text(/Finish the current round.*before changing modes/i)
    assert_text "Card 2 of 5"
    assert_selector ".guided-game-stage[data-game-state='running']"

    page.execute_script(<<~JAVASCRIPT)
      (() => {
        const root = document.querySelector("section.english-arcade[data-controller='english-arcade']")
        const controller = window.Stimulus.getControllerForElementAndIdentifier(root, 'english-arcade')
        const game = document.querySelector('.guided-card:not([hidden]) [data-guided-game-card]')
        controller.finishGuidedGameChoice(game.querySelector("[data-guided-game-options='best_answer'] [data-guided-game-correct='false']"))
      })()
    JAVASCRIPT
    assert_selector ".guided-game-stage[data-game-state='wrong']"
    assert_text(/Not the authored best phrase/i)
    assert_text "Score 100"
    assert_text "Streak 0"

    click_button "Next round"
    assert_text "Card 3 of 5"
    assert_selector ".guided-game-stage[data-game-state='running']"
    click_button "Next card"
    assert_text(/previous round was canceled when you changed cards/i)
    assert_text "Card 4 of 5"
    click_button "Start round"
    assert_selector ".guided-game-stage[data-game-state='running']"
    page.execute_script(<<~JAVASCRIPT)
      (() => {
        const root = document.querySelector("section.english-arcade[data-controller='english-arcade']")
        const controller = window.Stimulus.getControllerForElementAndIdentifier(root, 'english-arcade')
        controller.expireGuidedGameRound(document.querySelector('.guided-card:not([hidden]) [data-guided-game-card]'))
      })()
    JAVASCRIPT
    assert_selector ".guided-game-stage[data-game-state='timeout']"
    assert_text(/Time is up/i)
    assert_text "Streak 0"
  end

  test "expired guided sessions lock gameplay while leaving the dossier readable" do
    visit "/english-arcade"
    find("label[for='english-arcade-target-career']").click
    click_button "Play falling cards"
    click_button "Start round"

    page.execute_script(<<~JAVASCRIPT)
      (() => {
        const root = document.querySelector("section.english-arcade[data-controller='english-arcade']")
        const controller = window.Stimulus.getControllerForElementAndIdentifier(root, 'english-arcade')
        controller.expireSession()
      })()
    JAVASCRIPT
    assert_selector ".guided-game-stage[data-game-state='expired']"
    assert_button "Session ended", disabled: true
    assert_selector ".guided-card:not([hidden]) [data-guided-game-options='best_answer'] [data-guided-game-option][disabled]", count: 4, visible: :all
    assert_text "Gameplay is locked"

    result = page.evaluate_script(<<~JAVASCRIPT)
      (() => {
        const root = document.querySelector("section.english-arcade[data-controller='english-arcade']")
        const controller = window.Stimulus.getControllerForElementAndIdentifier(root, 'english-arcade')
        const game = document.querySelector('.guided-card:not([hidden]) [data-guided-game-card]')
        const start = game.querySelector('[data-guided-game-start]')
        const option = game.querySelector("[data-guided-game-options='best_answer'] [data-guided-game-option]")
        controller.startGuidedGame({ currentTarget: start })
        controller.nextGuidedGameRound({ preventDefault() {} })
        controller.finishGuidedGameChoice(option)
        controller.toggleGuidedPause()
        window.dispatchEvent(new KeyboardEvent('keydown', { key: '1', bubbles: true }))
        return {
          state: game.querySelector('[data-guided-game-stage]').dataset.gameState,
          rounds: controller.guidedGameRounds,
          score: controller.guidedGameScore,
          timeout: controller.guidedGameTimeout,
          clock: controller.guidedGameClock
        }
      })()
    JAVASCRIPT
    assert_equal "expired", result.fetch("state")
    assert_equal 0, result.fetch("rounds")
    assert_equal 0, result.fetch("score")
    assert_nil result.fetch("timeout")
    assert_nil result.fetch("clock")

    click_button "Next card"
    assert_text "Card 2 of 5"
    assert_selector ".guided-card:not([hidden]) .guided-game-stage[data-game-state='expired']"
    assert_button "Session ended", disabled: true
  end

  test "interview mode focuses on advanced resume experience instead of frontend basics" do
    visit "/english-arcade"
    find("label[for='english-arcade-target-interview']").click
    find("input[name='english_arcade_session[mode]'][value='timed_45']").click
    click_button "Play falling cards"

    assert_selector ".guided-card", count: 12, visible: :all
    prompts = page.evaluate_script("Array.from(document.querySelectorAll('.guided-card h3')).map((heading) => heading.textContent).join(' ')")
    assert_match(/100 million requests/i, prompts)
    assert_match(/event-driven communication/i, prompts)
    assert_match(/CI time.*fifteen applications/i, prompts)
    assert_match(/Yellow Team/i, prompts)
    assert_match(/2.5 million clients/i, prompts)
    refute_match(/\bHTML\b|\bCSS\b|box model|semantic markup/i, prompts)
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
