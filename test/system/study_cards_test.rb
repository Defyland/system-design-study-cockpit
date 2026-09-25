require "application_system_test_case"

class StudyCardsTest < ApplicationSystemTestCase
  setup do
    StudyCardRound.delete_all
  end

  test "study, reload, undo and explicitly replay completed cards" do
    visit study_cards_path
    assert_text "cards", wait: 10
    click_link "Estudar toda a trilha"
    assert_text "Escolha o formato", wait: 15
    click_button "Começar"
    assert_text "O que obj.print() imprime?", wait: 10
    assert_no_text "Com obj.print(), eu obtenho 6.", wait: 10
    find("summary").click
    assert_text "Com obj.print(), eu obtenho 6.", wait: 10
    save_screenshot Rails.root.join("tmp/screenshots/study-cards-desktop.png")
    click_button "Lido, próximo"
    assert_text "Como você preservaria o contexto", wait: 10
    page.driver.browser.navigate.refresh
    assert_text "Como você preservaria o contexto", wait: 10
    assert_equal 1, StudyCardRound.last.position
    click_button "Desfazer último avanço"
    assert_text "O que obj.print() imprime?", wait: 10
    assert_empty StudyCardRound.completed_keys(StudyCardRound.last.learner_key)
    click_button "Lido, próximo"
    within(".study-meta") { click_link "Biblioteca" }
    assert_text "Escolha o que estudar", wait: 15
    click_link "Estudar toda a trilha"
    assert_text "Escolha o formato", wait: 15
    choose "Revisar lidos por escolha"
    click_button "Começar"
    assert_text "Revisão escolhida", wait: 10
    assert_text "O que obj.print() imprime?", wait: 10
    click_button "Lido, próximo"
    assert_text "Rodada concluída.", wait: 10
    assert_equal 1, StudyCardRound.completed_keys(StudyCardRound.last.learner_key).size
  end

  test "a filtered round ends without recycling and swipe persists on mobile" do
    page.driver.browser.manage.window.resize_to(390, 844)
    keys = StudyCardCatalog.new.cards.select { |card| StudyCardCatalog.in_topic?(card, "english") }.map { |card| card[:id] }
    round = StudyCardRound.create!(learner_key: ENV["STUDY_COCKPIT_USERNAME"].presence || "anonymous", topic: "english", card_keys: keys)
    visit study_card_path(round)
    assert_selector "progress[value='0'][max='2']", wait: 10
    save_screenshot Rails.root.join("tmp/screenshots/study-cards-mobile.png")
    page.execute_script <<~JS
      const el = document.querySelector('.study-question h1');
      el.dispatchEvent(new TouchEvent('touchstart', { bubbles: true, touches: [new Touch({identifier: 1, target: el, clientX: 320, clientY: 200})] }));
      el.dispatchEvent(new TouchEvent('touchend', { bubbles: true, changedTouches: [new Touch({identifier: 1, target: el, clientX: 100, clientY: 205})] }));
    JS
    assert_text "How would you distinguish", wait: 10
    page.driver.browser.navigate.refresh
    assert_text "How would you distinguish", wait: 10
    assert_equal 1, StudyCardRound.last.position
    click_button "Lido, próximo"
    assert_text "Rodada concluída.", wait: 10
    assert_equal 1, StudyCardRound.count, "completion must not start another round automatically"
    click_link "Escolher novos cards"
    assert_no_selector ".study-question"
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1000)
  end
end
