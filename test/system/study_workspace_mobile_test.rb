require "application_system_test_case"
require "fileutils"
require "digest"

class StudyWorkspaceMobileTest < ApplicationSystemTestCase
  SCREENSHOTS = Rails.root.join("tmp/screenshots/study-workspace")

  setup do
    StudyCardRound.delete_all
    StudyCardBookmark.delete_all
    StudyQuizRound.delete_all
    StudyDocument.delete_all
    @document = StudyDocument.create!(kind: "ai_system", slug: "agentic-systems", title: "Agentic Systems",
      source_path: "areas/08-sistemas-ia/topics/agentic-systems.md", position: 0,
      body_checksum: "3630cc403654bf302007f1754883523ddaf7074aa0b0556a13a72f3935a74cb6",
      body_markdown: <<~MD)
        # Agentic Systems

        ## When to Use

        Use quando o sistema precisa planejar passos, chamar ferramentas e manter estado de tarefa.

        ## What Breaks First

        Loops, tool calls erradas, custo e falta de rollback de acao.

        ## Interview Trap

        Agente sem boundary vira automacao que ninguem consegue auditar.
      MD
    quiz_source = Rails.root.join("test/fixtures/files/study-workspace/dsa-pattern-selection.md").read
    @quiz_document = StudyDocument.create!(kind: "side_track_chapter", slug: "dsa-pattern-selection",
      title: "Chapter 01 - DSA Operating System and Pattern Selection",
      source_path: "areas/01-metodo-e-entrevistas/backend-interview-foundations/chapters/01-dsa-operating-system-and-pattern-selection.md",
      position: 1, body_checksum: Digest::SHA256.hexdigest(quiz_source), body_markdown: quiz_source)
    FileUtils.mkdir_p(SCREENSHOTS)
    page.driver.browser.manage.window.resize_to(390, 844)
  end

  teardown do
    page.driver.browser.manage.window.resize_to(1400, 1000)
  end

  test "library selection guide citation and map use a real imported source" do
    visit study_cards_path(topic: "kind:ai_system")
    assert_selector "input[name='source_ids[]'][value='#{@document.id}']", visible: :all
    assert_button "Escolher formato →", disabled: true
    capture("01-library-empty")
    fill_in "Buscar nesta lista", with: "fonte inexistente"
    assert_text "Nenhuma fonte corresponde à busca."
    assert_no_selector ".study-source-row", visible: true
    fill_in "Buscar nesta lista", with: ""
    assert_selector ".study-source-row", visible: true
    find("input[name='source_ids[]'][value='#{@document.id}']", visible: :all).check
    assert_button "Escolher formato →", disabled: false
    find("button", text: "Escolher formato →").scroll_to(:center)
    capture("01-library")
    page.execute_script("window.scrollTo(0, document.body.scrollHeight)")
    capture("01-library-selected")
    click_button "Escolher formato →"
    assert_text "1 fonte selecionada", wait: 15
    capture("02-configure")
    click_link "Alterar"
    assert_selector "input[name='source_ids[]'][value='#{@document.id}']:checked", visible: :all, wait: 15
    click_button "Escolher formato →"
    assert_text "1 fonte selecionada", wait: 15
    choose "Guia"
    click_button "Começar"
    assert_text "Use quando o sistema precisa planejar passos", wait: 15
    capture("03-guide")
    click_button "Abrir fonte citada"
    assert_selector "dialog[open]", text: /Use quando o sistema precisa planejar passos/
    capture("04-source-sheet")
    page.driver.browser.action.send_keys(:escape).perform
    assert_no_selector "dialog[open]"
    assert_selector "button[data-action='click->source-sheet#open']:focus", wait: 10
    click_button "Abrir fonte citada"
    assert_selector "dialog[open]"
    page.driver.browser.navigate.back
    assert_no_selector "dialog[open]"
    assert_selector "button[data-action='click->source-sheet#open']:focus", wait: 10
    visit study_map_path(topic: "kind:ai_system")
    assert_selector "[data-study-map-target='list']", visible: true
    assert_selector "[data-study-map-target='canvas']", visible: false
    click_button "Mapa"
    assert_selector "[data-study-map-target='canvas']", visible: true
    find("button[aria-label='Ampliar mapa']").click
    assert_match(/scale\(1\.2\)/, find("[data-study-map-target='transform']")[:style])
    click_button "Enquadrar"
    assert_match(/scale\(1\)/, find("[data-study-map-target='transform']")[:style])
    click_button "Lista"
    within(".study-map-list") do
      find("summary", text: /Agentic Systems/).click
      capture("09-map-list")
      click_link "Agentic Systems", match: :first
    end
    assert_selector ".study-map-preview", text: /Use quando o sistema precisa planejar passos/, wait: 15
    assert_match(/#study-map-preview\z/, page.current_url)
    assert_link "Abrir fonte", href: /section-library-/
    capture("09-map-preview")
    assert_no_horizontal_overflow
  end

  test "card bookmark reading undo completion review and saving error" do
    visit study_configure_path(topic: "all", source_ids: [@document.id])
    click_button "Começar"
    assert_selector ".study-question", text: /Agentic Systems/, wait: 15
    capture("05-card-closed")
    click_button "Guardar"
    assert_button "Guardado · remover marcação", wait: 15
    page.driver.browser.navigate.refresh
    assert_button "Guardado · remover marcação"
    find("summary", text: "Ler seção original").click
    assert_text "Use quando o sistema precisa planejar passos"
    capture("06-card-open")
    click_button "Lido, próximo"
    assert_selector "progress[value='1']", wait: 15
    click_button "Desfazer último avanço"
    assert_selector "progress[value='0']", wait: 15
    3.times do |index|
      click_button "Lido, próximo"
      assert_selector "progress[value='#{index + 1}']", wait: 15
    end
    assert_text "3 cards lidos."
    capture("11-completion")
    assert_equal 1, StudyCardRound.where(replay: false).count
    visit study_review_path
    assert_text "Guardados · 1", wait: 15
    find("button", text: "Revisar seleção").scroll_to(:center)
    capture("10-review")
    page.execute_script("window.scrollTo(0, document.body.scrollHeight)")
    capture("10-review-selection")
    click_button "Revisar seleção"
    assert_text "Revisão escolhida", wait: 15
    assert_equal [StudyDocumentCards.new(documents: [@document]).cards.first[:id]], StudyCardRound.last.card_keys
    assert_no_horizontal_overflow
  end

  test "quiz hides the answer until confirmation then persists authored explanation" do
    visit study_quizzes_path
    click_button "Começar perguntas inéditas"
    assert_selector ".study-quiz-form", wait: 15
    assert_button "Conferir resposta", disabled: true
    assert_no_text "Resposta canônica:"
    capture("07-quiz-before")
    find(".study-choice", text: /Obviously it is a sliding window/).find("input").choose
    assert_button "Conferir resposta", disabled: false
    click_button "Conferir resposta"
    assert_selector ".study-feedback", text: /Por que falha:/, wait: 15
    page.driver.browser.navigate.refresh
    assert_selector ".study-feedback", text: /Por que falha:/
    assert_link "Rever conceito", href: study_card_source_path(@quiz_document)
    find(".study-feedback p", text: /Por que falha:/).scroll_to(:center)
    capture("08-quiz-after")
    page.execute_script("window.scrollTo(0, document.body.scrollHeight)")
    capture("08-quiz-after-detail")
    visit study_review_path(kind: "errors")
    assert_text "Erros no quiz · 1", wait: 15
    assert_no_horizontal_overflow
  end

  test "desktop library guide cards quiz map and review use actual source material" do
    page.driver.browser.manage.window.resize_to(1400, 1000)
    visit study_cards_path(topic: "kind:ai_system")
    assert_text "Agentic Systems"
    capture_desktop("01-library")

    visit study_guide_path(document_id: @document.id)
    assert_text "Use quando o sistema precisa planejar passos"
    capture_desktop("02-guide")

    visit study_configure_path(topic: "kind:ai_system", source_ids: [@document.id])
    click_button "Começar"
    assert_selector ".study-question", text: /Agentic Systems/, wait: 15
    click_button "Guardar"
    assert_button "Guardado · remover marcação", wait: 15
    capture_desktop("03-card")

    visit study_quizzes_path
    click_button "Começar perguntas inéditas"
    assert_selector ".study-quiz-form", wait: 15
    find(".study-choice", text: /Obviously it is a sliding window/).find("input").choose
    click_button "Conferir resposta"
    assert_selector ".study-feedback", text: /Por que falha:/, wait: 15
    assert_link "Chapter 01 - DSA Operating System and Pattern Selection", href: study_card_source_path(@quiz_document)
    capture_desktop("04-quiz")

    visit study_map_path(topic: "kind:ai_system")
    assert_selector "[data-study-map-target='canvas']", visible: true
    capture_desktop("05-map")

    visit study_review_path
    assert_text "Guardados · 1", wait: 15
    capture_desktop("06-review")
  end

  test "long source and narrow viewports keep content and controls reachable" do
    @document.update!(body_markdown: @document.body_markdown + "\n## Código longo\n\n```ruby\n" + ("very_long_identifier_" * 20) + "\n```\n")
    [320, 430].each do |width|
      page.driver.browser.manage.window.resize_to(width, width == 320 ? 568 : 932)
      visit study_card_source_path(@document)
      assert_selector "pre code", text: /very_long_identifier_/, wait: 15
      assert_no_horizontal_overflow
      visit study_guide_path(document_id: @document.id, section: StudyDocumentCards.new(documents: [@document]).cards.last[:id])
      assert_selector ".study-guide-reading pre code", text: /very_long_identifier_/, wait: 15
      assert_no_horizontal_overflow
      visit study_map_path(topic: "kind:ai_system")
      assert_selector "[data-study-map-target='list']", visible: true
      assert_no_horizontal_overflow
    end
  end

  test "offline save leaves the card in place and retry advances only once" do
    visit study_configure_path(topic: "all", source_ids: [@document.id])
    click_button "Começar"
    assert_selector "progress[value='0']", wait: 15
    browser = page.driver.browser
    browser.execute_cdp("Network.enable")
    browser.execute_cdp("Network.emulateNetworkConditions", offline: true, latency: 0, downloadThroughput: 0, uploadThroughput: 0)
    click_button "Lido, próximo"
    assert_text "Não foi possível salvar.", wait: 15
    assert_equal 0, StudyCardRound.last.position
    capture("12-save-failure")
    browser.execute_cdp("Network.emulateNetworkConditions", offline: false, latency: 0, downloadThroughput: -1, uploadThroughput: -1)
    click_button "Tentar novamente"
    assert_selector "progress[value='1']", wait: 15
    assert_equal 1, StudyCardRound.last.position
    page.driver.browser.navigate.refresh
    assert_selector "progress[value='1']", wait: 15
  ensure
    browser&.execute_cdp("Network.emulateNetworkConditions", offline: false, latency: 0, downloadThroughput: -1, uploadThroughput: -1)
  end

  private

  def capture(name)
    assert_no_selector ".turbo-progress-bar", visible: true, wait: 5
    save_screenshot SCREENSHOTS.join("#{name}-390.png")
  end

  def capture_desktop(name)
    assert_no_selector ".turbo-progress-bar", visible: true, wait: 5
    save_screenshot SCREENSHOTS.join("desktop-#{name}.png")
  end

  def assert_no_horizontal_overflow
    assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth"), "page must not overflow horizontally"
  end
end
