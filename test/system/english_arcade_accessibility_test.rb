require "application_system_test_case"

class EnglishArcadeAccessibilityTest < ApplicationSystemTestCase
  setup do
    EnglishArcadeAttempt.delete_all
    EnglishArcadeCard.delete_all
    EnglishArcadeSession.delete_all
  end

  test "arcade controls are semantic, keyboard reachable, and do not leak answers" do
    visit "/english-arcade"

    assert_selector "section.english-arcade[data-controller='english-arcade']"
    assert_selector "h1"
    assert_selector "[role='radiogroup'][aria-label='Interview target']"
    assert_selector "[role='radiogroup'][aria-label='Session length']"
    assert_selector "button", minimum: 1
    assert_no_selector "[data-answer]"

    all("button").each do |button|
      assert(button.text.present? || button["aria-label"].present?, "button needs an accessible name")
    end

    find("label[for='english-arcade-target-dsa']").click
    assert_selector "input#english-arcade-target-dsa:checked", visible: :all
    click_button "Start closed-book session"
    assert_selector "form[data-english-arcade-target='form']"
    assert_no_selector "button", text: /voice|microphone|capture voice/i
    assert_no_selector "input[name*='spoken_text']", visible: :all
    fill_in "Typed answer", with: "I would state the invariant, make the trade-off explicit, and verify one counterexample before I commit to the implementation."
    fill_critical_ledger
    select "English directly", from: "english_arcade_attempt_english_directness"
    %w[clarity precision naturalness pragmatic_appropriateness technical_correctness].each do |axis|
      select "3", from: "english_arcade_attempt_self_#{axis}"
    end
    page.execute_script("window.dispatchEvent(new KeyboardEvent('keydown', { key: '2', bubbles: true }))")
    assert_operator all("input[name*='answer_choice']:checked", visible: :all).length, :==, 1
    page.execute_script(<<~JAVASCRIPT)
      const label = document.querySelector("label.arcade-choice")
      label.focus()
      label.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true }))
    JAVASCRIPT
    assert_selector "#feynman-title", text: /Feynman pass before the reveal/i
  end

  test "arcade layout remains usable at mobile, tablet, and desktop widths" do
    visit "/english-arcade"

    [ [ 390, 844 ], [ 768, 1024 ], [ 1440, 1000 ] ].each do |width, height|
      page.driver.browser.manage.window.resize_to(width, height)
      viewport_width = page.evaluate_script("window.innerWidth")
      scroll_width = page.evaluate_script("document.documentElement.scrollWidth")
      assert_operator scroll_width, :<=, viewport_width, "horizontal overflow at requested #{width}px (actual viewport #{viewport_width}px)"
      assert_selector "section.english-arcade[data-controller='english-arcade']"
    end

    find("label[for='english-arcade-target-career']").click
    click_button "Play falling cards"
    assert_selector ".guided-experience"
    [ [ 390, 844 ], [ 768, 1024 ], [ 1440, 1000 ] ].each do |width, height|
      page.driver.browser.manage.window.resize_to(width, height)
      viewport_width = page.evaluate_script("window.innerWidth")
      scroll_width = page.evaluate_script("document.documentElement.scrollWidth")
      assert_operator scroll_width, :<=, viewport_width, "guided horizontal overflow at requested #{width}px (actual viewport #{viewport_width}px)"
      assert_selector ".guided-board"
    end
  end

  test "mobile falling phrases stay readable within the level one separation budget" do
    visit "/english-arcade"
    find("label[for='english-arcade-target-career']").click
    click_button "Play falling cards"
    page.driver.browser.manage.window.resize_to(390, 844)
    click_button "Start round"

    geometry = page.evaluate_script(<<~JAVASCRIPT)
      (() => {
        const stage = document.querySelector('.guided-card:not([hidden]) [data-guided-game-stage]')
        const options = Array.from(stage.querySelectorAll("[data-guided-game-options='best_answer'] [data-guided-game-option]:not([hidden])"))
        const heights = options.map((option) => option.getBoundingClientRect().height)
        const stageRect = stage.getBoundingClientRect()
        const minimumHeight = Math.min(...heights)
        const travel = Number(stage.dataset.gameTravelPx) + (Number(stage.dataset.gameStartOffsetPercent) / 100 * minimumHeight)
        const separation = travel * Number(stage.dataset.gameStaggerMs) / Number(stage.dataset.gameFallDurationMs)
        return {
          count: options.length,
          heights,
          minimumHeight,
          maximumHeight: Math.max(...heights),
          separation,
          innerWidth: window.innerWidth,
          scrollWidth: document.documentElement.scrollWidth,
          maxRight: Math.max(...options.map((option) => option.getBoundingClientRect().right)),
          stageRight: stageRect.right
        }
      })()
    JAVASCRIPT

    assert_equal 4, geometry.fetch("count")
    assert_operator geometry.fetch("minimumHeight"), :>=, 48
    assert_operator geometry.fetch("maximumHeight"), :<, geometry.fetch("separation")
    assert_operator geometry.fetch("scrollWidth"), :<=, geometry.fetch("innerWidth")
    assert_operator geometry.fetch("maxRight"), :<=, geometry.fetch("stageRight")
  end

  test "reading pause clears the game clocks while preserving the remaining deadline" do
    visit "/english-arcade"
    find("label[for='english-arcade-target-career']").click
    click_button "Play falling cards"

    assert_current_path %r{/english_arcade\?session_id=\d+\z}
    page.driver.browser.manage.window.resize_to(1400, 1000)
    click_button "Start round"
    click_button "03 · Learning review"
    within "dialog.guided-learning-dialog[open]" do
      find("[data-guided-choice-index='0']").click
    end

    paused = page.evaluate_script(<<~JAVASCRIPT)
      (() => {
        const root = document.querySelector("section.english-arcade[data-controller='english-arcade']")
        const controller = window.Stimulus.getControllerForElementAndIdentifier(root, 'english-arcade')
        const stage = document.querySelector('.guided-card:not([hidden]) [data-guided-game-stage]')
        return {
          state: stage.dataset.gameState,
          readingPaused: controller.guidedReadingPaused,
          stagePaused: stage.classList.contains('is-paused'),
          timeout: controller.guidedGameTimeout,
          clock: controller.guidedGameClock,
          remaining: controller.guidedGameRemainingMs,
          deadline: Number(stage.dataset.gameDeadlineMs)
        }
      })()
    JAVASCRIPT
    assert_equal "running", paused.fetch("state")
    assert_equal true, paused.fetch("readingPaused")
    assert_equal true, paused.fetch("stagePaused")
    assert_nil paused.fetch("timeout")
    assert_nil paused.fetch("clock")
    assert_operator paused.fetch("remaining"), :>, 0
    assert_operator paused.fetch("remaining"), :<=, paused.fetch("deadline")

    within "dialog.guided-learning-dialog[open]" do
      find("[data-guided-choice-index='1']").click
    end
    paused_again = page.evaluate_script(<<~JAVASCRIPT)
      (() => {
        const root = document.querySelector("section.english-arcade[data-controller='english-arcade']")
        const controller = window.Stimulus.getControllerForElementAndIdentifier(root, 'english-arcade')
        return {
          timeout: controller.guidedGameTimeout,
          clock: controller.guidedGameClock,
          remaining: controller.guidedGameRemainingMs
        }
      })()
    JAVASCRIPT
    assert_nil paused_again.fetch("timeout")
    assert_nil paused_again.fetch("clock")
    assert_in_delta paused.fetch("remaining"), paused_again.fetch("remaining"), 5

    within "dialog.guided-learning-dialog[open]" do
      click_button "Close and keep reviewing"
    end
    click_button "Resume"
    resumed = page.evaluate_script(<<~JAVASCRIPT)
      (() => {
        const root = document.querySelector("section.english-arcade[data-controller='english-arcade']")
        const controller = window.Stimulus.getControllerForElementAndIdentifier(root, 'english-arcade')
        return { readingPaused: controller.guidedReadingPaused, remaining: controller.guidedGameRemainingMs }
      })()
    JAVASCRIPT
    assert_equal false, resumed.fetch("readingPaused")
    assert_operator resumed.fetch("remaining"), :>, 1
    assert_in_delta paused_again.fetch("remaining"), resumed.fetch("remaining"), 5
  end

  test "reduced motion uses static choices with the same fair playable deadline" do
    visit "/english-arcade"
    find("label[for='english-arcade-target-career']").click
    click_button "Play falling cards"

    assert_current_path %r{/english_arcade\?session_id=\d+\z}
    page.execute_script(<<~JAVASCRIPT)
      window.matchMedia = (query) => ({
        matches: query.includes('prefers-reduced-motion'),
        media: query,
        onchange: null,
        addListener: () => {},
        removeListener: () => {},
        addEventListener: () => {},
        removeEventListener: () => {},
        dispatchEvent: () => false
      })
    JAVASCRIPT

    click_button "Start round"
    assert_selector ".guided-game-stage.is-static-round[data-game-state='running']"
    assert_selector "[data-guided-game-options='best_answer'] [data-guided-game-option]:not([hidden])", count: 4, visible: :all
    deadline = page.evaluate_script("Number(document.querySelector('.guided-card:not([hidden]) [data-guided-game-stage]').dataset.gameDeadlineMs)")
    animation = page.evaluate_script("getComputedStyle(document.querySelector('.guided-card:not([hidden]) [data-guided-game-option]')).animationName")
    assert_operator deadline, :>=, 7000
    assert_equal "none", animation

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
