require "application_system_test_case"

class StudyCardsTest < ApplicationSystemTestCase
  setup do
    StudyCardRound.delete_all
  end

  test "study, reload, undo and explicitly replay completed cards" do
    visit study_cards_path
    assert_text "cards"
    click_button "Estudar inéditos · até 50"
    assert_text "O que obj.print() imprime?"
    assert_no_text "Com obj.print(), eu obtenho 6."
    find("summary").click
    assert_text "Com obj.print(), eu obtenho 6."
    save_screenshot Rails.root.join("tmp/screenshots/study-cards-desktop.png")
    click_button "Feito, próximo"
    assert_text "Como você preservaria o contexto"
    page.driver.browser.navigate.refresh
    assert_text "Como você preservaria o contexto"
    assert_equal 1, StudyCardRound.last.position
    click_button "Desfazer último avanço"
    assert_text "O que obj.print() imprime?"
    assert_empty StudyCardRound.completed_keys(StudyCardRound.last.learner_key)
    click_button "Feito, próximo"
    click_link "Assuntos e rodadas"
    click_button "Repetir feitos"
    assert_text "Repetição escolhida"
    assert_text "O que obj.print() imprime?"
    click_button "Feito, próximo"
    assert_text "Rodada concluída."
    assert_equal 1, StudyCardRound.completed_keys(StudyCardRound.last.learner_key).size
  end

  test "a filtered round ends without recycling and swipe persists on mobile" do
    page.driver.browser.manage.window.resize_to(390, 844)
    visit study_cards_path
    select "Inglês", from: "O que você quer praticar?"
    click_button "Estudar inéditos · até 50"
    assert_text "0 de 2 feitos"
    save_screenshot Rails.root.join("tmp/screenshots/study-cards-mobile.png")
    page.execute_script <<~JS
      const el = document.querySelector('.study-question h1');
      el.dispatchEvent(new TouchEvent('touchstart', { bubbles: true, touches: [new Touch({identifier: 1, target: el, clientX: 320, clientY: 200})] }));
      el.dispatchEvent(new TouchEvent('touchend', { bubbles: true, changedTouches: [new Touch({identifier: 1, target: el, clientX: 100, clientY: 205})] }));
    JS
    assert_text "How would you distinguish"
    page.driver.browser.navigate.refresh
    assert_text "How would you distinguish"
    assert_equal 1, StudyCardRound.last.position
    click_button "Feito, próximo"
    assert_text "Rodada concluída."
    click_link "Escolher próxima rodada"
    select "Inglês", from: "O que você quer praticar?"
    click_button "Estudar inéditos · até 50"
    assert_text "Você concluiu os inéditos deste assunto"
    assert_no_selector ".study-question"
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1000)
  end
end
