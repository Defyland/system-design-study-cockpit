require "application_system_test_case"

class ArcadeWarmupTest < ApplicationSystemTestCase
  test "warm-up validates associations and answers before handing off the selected role" do
    visit arcade_warmup_path(interview_role: "backend")
    counts = %w[ArcadeLesson.count ArcadeExerciseEvent.count ArcadeStageState.count EnglishArcadeAttempt.count EnglishArcadeSession.count]
    assert_no_difference(counts) do
      click_button "Continue to short response"
      assert_no_field "Short response"
      fill_in "Association 1", with: "water"
      fill_in "Association 2", with: " WATER "
      fill_in "Association 3", with: "river"
      click_button "Continue to short response"
      assert_no_field "Short response"
      fill_in "Association 2", with: "swimming"
      click_button "Continue to short response"
      select "water", from: "Choose an association"
      click_button "Continue to interview"
      assert_no_field "Interview response"
      fill_in "Short response", with: "Water reminds me of queues because both can absorb a changing flow."
      click_button "Continue to interview"
      assert_text "reliability"
      check "warmup-interview-aloud"
      click_button "Continue to follow-up"
      assert_field "Follow-up response"
      assert_no_field "Interview response"
      check "warmup-follow-up-aloud"
      click_button "Reflect on this round"
      assert_button "Try the interview answer again"
      click_button "Try the interview answer again"
      assert_field "Interview response"
      assert_unchecked_field "warmup-interview-aloud"
      fill_in "Interview response", with: "I make retry boundaries explicit and verify them with production signals."
      click_button "Continue to follow-up"
      assert_unchecked_field "warmup-follow-up-aloud"
      fill_in "Follow-up response", with: "I would explain the idempotency boundary and how retries are checked."
      click_button "Reflect on this round"
    end

    assert_difference("ArcadeLesson.count", 1) do
      click_button "Start interview rehearsal"
      assert_current_path %r{/arena/lessons/\d+}
    end
    lesson = ArcadeLesson.order(:id).last
    assert_equal "interview", lesson.target_mode
    assert lesson.plan.all? { |entry| entry.fetch("card_key").start_with?("resume-backend-") }
  end

  test "another word resets the round and the warm-up fits a narrow viewport" do
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: false)
    visit arcade_warmup_path
    fill_in "Association 1", with: "water"
    fill_in "Association 2", with: "swimming"
    fill_in "Association 3", with: "river"
    click_button "Continue to short response"
    select "water", from: "Choose an association"
    check "warmup-short-aloud"
    click_button "Continue to interview"
    check "warmup-interview-aloud"
    click_button "Continue to follow-up"
    check "warmup-follow-up-aloud"
    click_button "Reflect on this round"
    click_button "Practice another word"
    assert_field "Association 1", with: ""
    assert_field "Association 2", with: ""
    assert_field "Association 3", with: ""
    assert_no_text "duck"
    clipped = page.evaluate_script(<<~JS)
      [...document.querySelectorAll('.arena-warmup-step:not([hidden]), .arena-warmup input, .arena-warmup select, .arena-warmup button')]
        .filter(element => element.getClientRects().length)
        .filter(element => {
          const box = element.getBoundingClientRect();
          return box.left < 0 || box.right > document.documentElement.clientWidth;
        }).map(element => element.tagName)
    JS
    assert_empty clipped
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end
end
