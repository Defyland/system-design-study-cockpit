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
    click_button "Start guided study"
    assert_selector ".guided-experience"
    [ [ 390, 844 ], [ 768, 1024 ], [ 1440, 1000 ] ].each do |width, height|
      page.driver.browser.manage.window.resize_to(width, height)
      viewport_width = page.evaluate_script("window.innerWidth")
      scroll_width = page.evaluate_script("document.documentElement.scrollWidth")
      assert_operator scroll_width, :<=, viewport_width, "guided horizontal overflow at requested #{width}px (actual viewport #{viewport_width}px)"
      assert_selector ".guided-board"
    end
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
