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
    question = item.dig("learning", "reasoning_questions").first
    assert_text "How I think through this"
    within ".arena-reasoning" do
      assert_selector "details", count: 4
      assert_no_text question.fetch("answer")
      find("summary", text: question.fetch("question")).click
      assert_text question.fetch("answer")
    end

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
    assert_selector "[data-arena-word-count]", text: "#{item.fetch('best_answer').split.length} words"
    assert_text "Draft saved in this browser"
    page.driver.browser.navigate.refresh
    assert_field "Your answer", with: item.fetch("best_answer")
    assert_field "arena-self-rating", with: "4"
    assert_text "Draft restored from this browser"
    click_button "Submit production"

    assert_selector ".arena-feedback:not([hidden])", text: "Recall recorded"
    assert_text "Automatic phrase recall"
    assert_text "Meaning, grammar, fluency, and pronunciation are not assessed"
    assert_selector "[data-arena-production-diff]"
    assert_text "Resume facts used in this answer"
    within ".arena-feedback .arena-reasoning" do
      find("summary", text: question.fetch("question")).click
      assert_text question.fetch("answer")
    end
    assert_empty page.evaluate_script("Object.keys(localStorage).filter(key => key.startsWith('arena:draft:v1:'))")
    click_button "Continue"

    assert_selector "[data-arcade-lesson-target='stage']", text: /transfer/i
    assert_text item.dig("follow_up", "prompt")
    assert_no_selector ".arena-learning-card"
  end

  test "failed submission retains the draft and retry records it once" do
    open_recall
    fill_in "Your answer", with: "I led a frontend migration across five squads and reduced deployment time through independent delivery."
    select "3 · good", from: "arena-self-rating"
    page.execute_script(<<~JS)
      const originalFetch = window.fetch.bind(window);
      window.fetch = (url, options) => {
        if (String(url).endsWith('/results')) {
          window.fetch = originalFetch;
          return new Promise((_resolve, reject) => { window.rejectArenaSave = () => reject(new Error('Test connection lost')); });
        }
        return originalFetch(url, options);
      };
    JS
    click_button "Submit production"
    assert_button "Saving answer…", disabled: true
    assert_selector "[data-arcade-lesson-target='exercise'][aria-busy='true'][inert]"
    page.execute_script("window.rejectArenaSave()")
    assert_text "Answer not saved. Try again."
    assert_button "Submit production", disabled: false
    assert_no_selector "[data-arcade-lesson-target='exercise'][inert]"
    assert_equal 1, ArcadeExerciseEvent.count
    assert_equal 1, page.evaluate_script("Object.keys(localStorage).filter(key => key.startsWith('arena:draft:v1:')).length")
    click_button "Retry"
    assert_selector ".arena-feedback:not([hidden])", text: "Model answer:"
    assert_equal 2, ArcadeExerciseEvent.count
    assert_empty page.evaluate_script("Object.keys(localStorage).filter(key => key.startsWith('arena:draft:v1:'))")
  end

  test "unavailable draft storage does not claim a save or block answering" do
    open_recall
    page.execute_script("Storage.prototype.setItem = function () { throw new Error('Storage unavailable'); }")
    fill_in "Your answer", with: "A short draft"
    assert_selector "[data-arena-word-count]", text: "3 words"
    assert_selector "[data-arena-draft-status][data-state='error']", text: "Draft could not be saved"
    assert_no_text "Draft saved in this browser"
    assert_button "Submit production", disabled: false
  end

  test "a saved result followed by a stale refresh offers a new lesson instead of a retry loop" do
    visit arena_path
    choose "arena-interview-role-frontend"
    click_button "Interview mode"
    click_button "Got it"
    assert_selector ".arena-feedback:not([hidden])"
    assert_equal 1, ArcadeExerciseEvent.count
    page.execute_script(<<~JS)
      const originalFetch = window.fetch.bind(window);
      window.fetch = (url, options) => String(url).endsWith('.json')
        ? Promise.resolve(new Response(JSON.stringify({ error: 'stale_content' }), { status: 422, headers: { 'Content-Type': 'application/json' } }))
        : originalFetch(url, options);
    JS

    click_button "Continue"

    assert_text "Study material updated"
    assert_link "Return to Arena", href: arena_path
    assert_no_button "Retry"
    assert_no_selector "[data-arcade-lesson-target='exercise']:not([hidden])"
    assert_equal 1, ArcadeExerciseEvent.count
    click_link "Return to Arena"
    assert_current_path arena_path
  end

  private

  def open_recall
    lesson = ArcadeLessonComposer.new(learner_key: ENV["STUDY_COCKPIT_USERNAME"].presence || "anonymous").call(
      target_mode: "interview", interview_role: "frontend", size: 2, new_cards: 1
    )
    visit arcade_lesson_path(lesson)
    page.execute_script("localStorage.clear()")
    click_button "Got it"
    assert_selector ".arena-feedback:not([hidden])"
    click_button "Continue"
    assert_selector "[data-arcade-lesson-target='stage']", text: /produce/i
  end
end
