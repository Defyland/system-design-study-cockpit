require "application_system_test_case"

class StudyCardLibraryTest < ApplicationSystemTestCase
  setup do
    StudyCardRound.delete_all
  end

  test "Ruby Rails Go and Elixir use the existing interview answers" do
    visit study_cards_path
    save_screenshot Rails.root.join("tmp/screenshots/study-cards-library.png")
    select "Ruby", from: "Filtrar por trilha"
    click_button "Filtrar"
    assert_selector "input[name='topic'][value='ruby']", visible: false, wait: 20
    click_button "Nova rodada · até 50"
    assert_text "What is the practical difference between a proc and a lambda?", wait: 10
    find("summary", text: "Ver raciocínio e resposta", match: :first).click
    assert_text "a lambda checks its arity while a proc does not", wait: 10
    save_screenshot Rails.root.join("tmp/screenshots/study-cards-ruby.png")
    click_button "Lido, próximo"
    page.driver.browser.navigate.refresh
    assert_no_text "What is the practical difference between a proc and a lambda?", wait: 10
    within(".study-meta") { click_link "Biblioteca" }
    select "Ruby on Rails", from: "Filtrar por trilha"
    click_button "Filtrar"
    assert_selector "input[name='topic'][value='rails']", visible: false, wait: 20
    click_button "Nova rodada · até 50"
    assert_selector ".study-side-panel", text: /Ruby on Rails/, wait: 20
    within(".study-meta") { click_link "Biblioteca" }
    select "Golang", from: "Filtrar por trilha"
    click_button "Filtrar"
    assert_selector "input[name='topic'][value='golang']", visible: false, wait: 20
    click_button "Nova rodada · até 50"
    assert_selector ".study-side-panel", text: /Golang/, wait: 20
    within(".study-meta") { click_link "Biblioteca" }
    select "Elixir", from: "Filtrar por trilha"
    click_button "Filtrar"
    assert_selector "input[name='topic'][value='elixir']", visible: false, wait: 20
    click_button "Nova rodada · até 50"
    assert_selector ".study-side-panel", text: /Elixir/, wait: 20
  end
  test "library cards render original prose and code and link to the complete document" do
    document = StudyDocument.create!(kind: "reference_document", slug: "ruby-card-evidence", title: "Ruby closure notes",
      source_path: "notes/ruby-card-evidence.md", position: 0, body_checksum: "card-evidence",
      body_markdown: "# Ruby closure notes\n\n## Return boundary\n\nI choose a lambda when the return boundary must stay local.\n\n```ruby\ncallback = -> { 42 }\n```\n")
    key = StudyDocumentCards.new(documents: [ document ]).cards.first.fetch(:id)
    round = StudyCardRound.create!(learner_key: ENV["STUDY_COCKPIT_USERNAME"].presence || "anonymous",
      topic: "ruby", card_keys: [ key ])
    visit study_card_path(round)
    assert_text "Ruby closure notes", wait: 10
    find("summary", text: "Ler seção original").click
    assert_text "I choose a lambda when the return boundary must stay local.", wait: 10
    assert_selector "pre code", text: "callback = -> { 42 }"
    assert_link "Abrir trecho no original", href: /#{Regexp.escape(study_card_source_path(document))}#section-/
    visit study_card_source_path(document)
    assert_text "I choose a lambda when the return boundary must stay local.", wait: 10
    assert_selector "pre code", text: "callback = -> { 42 }"
    visit study_card_path(round)
    click_button "Lido, próximo"
    page.driver.browser.navigate.refresh
    assert_text "Rodada concluída.", wait: 10
    assert_equal 1, round.reload.position
  end
end
