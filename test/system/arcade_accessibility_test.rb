require "application_system_test_case"

class ArcadeAccessibilityTest < ApplicationSystemTestCase
  setup do
    ArcadeExerciseEvent.delete_all
    ArcadeLesson.delete_all
    ArcadeStageState.delete_all
    @learner_key = ENV["STUDY_COCKPIT_USERNAME"].presence || "anonymous"
  end

  test "Arena hub has named controls and no horizontal overflow at supported widths" do
    visit "/arena"

    assert_selector "section.arena-hub"
    assert_named_buttons

    [ [ 360, 800 ], [ 390, 844 ], [ 768, 1024 ], [ 1440, 1000 ] ].each do |width, height|
      page.driver.browser.manage.window.resize_to(width, height)
      assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, page.evaluate_script("window.innerWidth"), "horizontal overflow at #{width}px"
      assert_named_buttons
      if width == 360
        assert page.evaluate_script(<<~JAVASCRIPT), "primary practice paths should stack at 360px"
          (() => {
            const cards = [
              document.querySelector('.arena-practice-card'),
              document.querySelector('.arena-interview-card')
            ].filter(Boolean).map((card) => card.getBoundingClientRect())
            return cards.length === 2 && cards[1].top > cards[0].top && Math.abs(cards[1].left - cards[0].left) <= 1
          })()
        JAVASCRIPT
      end
    end
  end

  test "interview entry point exposes the supported role lenses and defaults to full stack" do
    visit "/arena"

    assert_selector "form.arena-interview-form input[name='lesson[interview_role]'][value='frontend']"
    assert_selector "form.arena-interview-form input[name='lesson[interview_role]'][value='backend']"
    assert_selector "form.arena-interview-form input[name='lesson[interview_role]'][value='fullstack'][checked]"
    assert_selector "form.arena-interview-form input[name='lesson[interview_role]'][value='smarttv']"
    assert_selector "form.arena-interview-form input[name='lesson[target_mode]'][value='interview']", visible: :all
  end

  test "lesson controls support keyboard completion and Escape opens a focused exit dialog" do
    lesson = create_lesson(%w[meet meet])
    visit arcade_lesson_path(lesson)

    assert_selector "[data-arcade-lesson-target='position']", text: "1"
    assert_equal "BUTTON", page.evaluate_script("document.activeElement.tagName")
    find(".arena-exercise button").send_keys(:space)
    assert_selector ".arena-feedback:not([hidden])", wait: 5

    find("[data-arena-continue]").send_keys(:enter)
    assert_selector "[data-arcade-lesson-target='position']", text: "2", wait: 5
    page.execute_script("document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }))")
    assert_selector "dialog.arena-dialog[open]", wait: 5
    assert_match(/Keep going/i, page.evaluate_script("document.activeElement.textContent"))
    find("dialog.arena-dialog[open] button").send_keys(:enter)
    assert_no_selector "dialog.arena-dialog[open]"

    find(".arena-exercise button").send_keys(:space)
    assert_selector ".arena-feedback:not([hidden])", wait: 5
    find("[data-arena-continue]").send_keys(:enter)
    assert_selector ".arena-results:not([hidden])", wait: 5
    assert_text(/Lesson complete/i)
  end

  test "reduced-motion rain collapses to a static single-column choice list" do
    visit "/arena"
    page.driver.browser.execute_cdp(
      "Emulation.setEmulatedMedia",
      features: [ { name: "prefers-reduced-motion", value: "reduce" } ]
    )
    click_button "Rain round only"

    assert_selector ".arena-rain", wait: 5
    assert_operator all(".arena-rain-choice").length, :>=, 1
    motion = page.evaluate_script(<<~JAVASCRIPT)
      (() => {
        const choice = document.querySelector('.arena-rain-choice')
        const lanes = document.querySelector('.arena-rain-lanes')
        const style = getComputedStyle(choice)
        return {
          animationDuration: style.animationDuration,
          transform: style.transform,
          columns: getComputedStyle(lanes).gridTemplateColumns
        }
      })()
    JAVASCRIPT
    assert_operator motion.fetch("animationDuration").to_f, :<=, 0.01
    assert_equal "none", motion.fetch("transform")
    assert_equal 1, motion.fetch("columns").split(" ").length
    assert_named_buttons
  end

  private

  def assert_named_buttons
    unnamed = page.evaluate_script(<<~JAVASCRIPT)
      Array.from(document.querySelectorAll('button')).filter((button) => {
        const name = (button.innerText || button.getAttribute('aria-label') || '').trim()
        return !name
      }).map((button) => button.outerHTML)
    JAVASCRIPT
    assert_empty unnamed, "every button needs visible text or an aria-label"
  end

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
      seed: "system-accessibility",
      started_at: Time.current,
      exercises_total: entries.length,
      plan: entries
    )
  end
end
