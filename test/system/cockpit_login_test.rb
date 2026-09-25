require "application_system_test_case"

class CockpitLoginTest < ApplicationSystemTestCase
  setup do
    @original_username = ENV["STUDY_COCKPIT_USERNAME"]
    @original_password = ENV["STUDY_COCKPIT_PASSWORD"]
    ENV["STUDY_COCKPIT_USERNAME"] = "study"
    ENV["STUDY_COCKPIT_PASSWORD"] = "test-secret"
    StudyCardRound.delete_all
  end

  teardown do
    ENV["STUDY_COCKPIT_USERNAME"] = @original_username
    ENV["STUDY_COCKPIT_PASSWORD"] = @original_password
  end

  test "login protects cards, keeps the existing learner progress, and logout revokes access" do
    visit study_cards_path
    assert_text "Entrar no Study Cockpit"
    assert_current_path login_path

    fill_in "Usuário", with: "study"
    fill_in "Senha", with: "wrong"
    click_button "Entrar"
    assert_text "Credenciais inválidas"
    visit chapters_path
    assert_current_path login_path

    fill_in "Usuário", with: "study"
    fill_in "Senha", with: "test-secret"
    click_button "Entrar"
    assert_current_path chapters_path
    visit study_cards_path
    select "Ruby", from: "O que você quer praticar?"
    click_button "Estudar inéditos · até 50"
    click_button "Feito, próximo"
    assert_text "1 de", wait: 10
    round = StudyCardRound.last
    assert_equal "study", round.learner_key
    assert_equal 1, round.position

    page.driver.browser.navigate.refresh
    assert_equal 1, StudyCardRound.last.position
    click_button "Sair"
    visit study_card_path(round)
    assert_current_path login_path

    fill_in "Usuário", with: "study"
    fill_in "Senha", with: "test-secret"
    click_button "Entrar"
    assert_current_path study_card_path(round)
    assert_equal 1, StudyCardRound.last.position
  end
end
