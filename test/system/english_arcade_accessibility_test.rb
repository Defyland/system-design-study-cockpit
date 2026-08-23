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
  end
end
