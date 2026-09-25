require "test_helper"

class StudyWorkspaceTest < ActionDispatch::IntegrationTest
  setup do
    StudyCardRound.delete_all
    StudyCardBookmark.delete_all
    StudyQuizRound.delete_all
    StudyDocument.delete_all
    @document = StudyDocument.create!(kind: StudyDocument.kinds.keys.first, slug: "workspace-source", title: "Workspace source", source_path: "workspace/source.md", body_markdown: "# First section\nOriginal first paragraph.\n\n# Second section\nOriginal second paragraph.\n", body_checksum: "workspace-test", position: 0)
    @learner = ENV["STUDY_COCKPIT_USERNAME"].presence || "anonymous"
  end

  test "source selection limits a persisted round and citation opens the exact section" do
    post study_cards_path, params: { topic: "all", mode: "new", source_ids: [@document.id] }
    round = StudyCardRound.last
    assert_equal [@document.id], round.source_ids
    assert round.card_keys.all? { |key| key.start_with?("library-") }
    get study_card_path(round)
    assert_response :success
    assert_select "a[href*='section-']"
    assert_select "aside", text: /Workspace source/
    second = StudyDocument.create!(kind: @document.kind, slug: "another-source", title: "Another source", source_path: "workspace/another.md", body_markdown: "# Other\nDifferent text.\n", body_checksum: "another-test", position: 1)
    post study_cards_path, params: { topic: "all", mode: "new", source_ids: [second.id] }
    assert_equal [second.id], StudyCardRound.last.source_ids
    assert (round.card_keys & StudyCardRound.last.card_keys).empty?
  end

  test "guide and map preserve exact source section and unavailable source is 404" do
    sections = StudyDocumentCards.new(documents: [@document]).cards
    section_path = "#{study_card_source_path(@document)}#section-#{sections.last[:id]}"
    get study_guide_path(document_id: @document.id, section: sections.last[:id])
    assert_response :success
    assert_select ".study-guide-reading", text: /Original second paragraph/
    assert_select "a[href='#{section_path}']"
    get section_path
    assert_response :success
    assert_select "section[id='section-#{sections.last[:id]}']", text: /Original second paragraph/
    get study_map_path(topic: "all")
    assert_response :success
    assert_select "a[href='#{section_path}']"
    get study_card_source_path(999_999_999)
    assert_response :not_found
  end

  test "bookmark review is explicit and unbookmarking preserves completed reading" do
    card_key = StudyCardCatalog.new.cards.first.fetch(:id)
    post study_bookmarks_path, params: { card_key: card_key }
    assert_equal [card_key], StudyCardBookmark.for_learner(@learner).pluck(:card_key)
    get study_review_path
    assert_response :success
    assert_equal 0, StudyCardRound.count
    post start_study_review_path, params: { kind: "saved" }
    round = StudyCardRound.last
    assert_equal [card_key], round.card_keys
    assert round.replay?
    StudyCardRound.create!(learner_key: @learner, topic: "all", card_keys: [card_key], position: 1)
    delete study_bookmark_path(card_key)
    assert_empty StudyCardBookmark.for_learner(@learner)
    assert_includes StudyCardRound.completed_keys(@learner), card_key
  end

  test "quiz records authored wrong answer once and a voluntary correct review resolves error" do
    quiz = StudyQuizCatalog.new
    card = quiz.cards.first
    wrong = quiz.choices(card).find { |choice| !choice["correct"] }
    correct = quiz.choices(card).find { |choice| choice["correct"] }
    round = StudyQuizRound.create!(learner_key: @learner, topic: "all", card_keys: [card[:id]])
    patch study_quiz_path(round), params: { position: 0, card_key: card[:id], direction: "answer", choice_id: wrong["id"] }
    assert_equal false, round.reload.responses.dig(card[:id], "correct")
    patch study_quiz_path(round), params: { position: 0, card_key: card[:id], direction: "answer", choice_id: correct["id"] }
    assert_equal wrong["id"], round.reload.responses.dig(card[:id], "choice_id"), "repeated answer must not change the first attempt"
    get study_quiz_path(round)
    assert_select ".study-feedback", text: /#{Regexp.escape(wrong['why_wrong'])}/
    assert_equal 0, StudyCardRound.count
    patch study_quiz_path(round), params: { position: 0, card_key: card[:id], direction: "next" }
    assert round.reload.finished?
    assert_includes StudyQuizRound.error_keys(@learner), card[:id]
    post start_study_review_path, params: { kind: "errors" }
    review = StudyQuizRound.last
    assert_equal "errors", review.mode
    patch study_quiz_path(review), params: { position: 0, card_key: card[:id], direction: "answer", choice_id: correct["id"] }
    assert_empty StudyQuizRound.error_keys(@learner)
  end

  test "quiz source selection never substitutes unrelated Arcade questions" do
    assert_no_difference "StudyQuizRound.count" do
      post study_quizzes_path, params: { topic: "all", mode: "new", source_ids: [@document.id] }
      assert_redirected_to study_quizzes_path
    end
    path = StudyQuizCatalog.new.cards.first.dig(:coaching, "sources").first.fetch("path")
    source = StudyDocument.create!(kind: @document.kind, slug: "arcade-source", title: "Arcade source", source_path: path,
      body_markdown: "# Source\nOriginal source text.\n", body_checksum: "arcade-source", position: 2)
    post study_quizzes_path, params: { topic: "all", mode: "new", source_ids: [source.id] }
    round = StudyQuizRound.last
    assert_equal [source.id], round.source_ids
    catalog = StudyQuizCatalog.new
    assert round.card_keys.all? { |key| catalog.source_document_ids(catalog.find(key)).include?(source.id) }
    assert_no_difference "StudyQuizRound.count" do
      post study_quizzes_path, params: { topic: "all", mode: "new", source_ids: [source.id] }
      assert_redirected_to study_quiz_path(round)
      post start_study_workspace_path, params: { topic: "all", format: "quiz", source_ids: [source.id] }
      assert_redirected_to study_quiz_path(round)
    end
  end

  test "workspace routes expose guide map quiz and review" do
    get "/study-cards/guide"
    assert_response :success
    get "/study-cards/map"
    assert_response :success
    get "/study-cards/quiz"
    assert_response :success
    get "/study-cards/review"
    assert_response :success
  end

  test "whole topic format starts authored interview cards without selected documents" do
    get study_configure_path(topic: "frontend", scope: "all")
    assert_response :success
    post start_study_workspace_path, params: { topic: "frontend", scope: "all", format: "cards", mode: "new" }
    assert_redirected_to study_card_path(StudyCardRound.last)
    assert_equal "rippling-this", StudyCardRound.last.card_keys.first
    assert_empty StudyCardRound.last.source_ids
    post start_study_workspace_path, params: { topic: "all", scope: "all", format: "quiz" }
    assert_redirected_to study_quiz_path(StudyQuizRound.last)
    assert_empty StudyQuizRound.last.source_ids
    post start_study_workspace_path, params: { topic: "frontend", scope: "all", format: "guide" }
    assert_redirected_to study_guide_path(topic: "frontend")
    post start_study_workspace_path, params: { topic: "frontend", scope: "all", format: "map" }
    assert_redirected_to study_map_path(topic: "frontend")
  end

  test "guide keeps selected source scope and leaves empty tabs without a reading" do
    second = StudyDocument.create!(kind: @document.kind, slug: "second-selected", title: "Second selected", source_path: "workspace/second.md", body_markdown: "# Second\nOriginal second source.\n", body_checksum: "second-selected", position: 1)
    third = StudyDocument.create!(kind: @document.kind, slug: "third-unselected", title: "Third unselected", source_path: "workspace/third.md", body_markdown: "# Third\nUnselected source.\n", body_checksum: "third-unselected", position: 2)
    get study_guide_path(topic: "all", document_id: @document.id, source_ids: [@document.id, second.id], tab: "Compare")
    assert_response :success
    assert_select "form[action='#{study_guide_path}'] input[name='source_ids[]'][value='#{@document.id}']"
    assert_select "form[action='#{study_guide_path}'] input[name='source_ids[]'][value='#{second.id}']"
    assert_select "select[name='document_id'] option[value='#{third.id}']", false
    assert_select ".study-guide-reading", false
    assert_select ".study-source-pane", text: /Nenhuma seção desta categoria/
    get study_map_path(topic: "all", source_ids: [@document.id, second.id])
    assert_select "form[action='#{study_map_path}'] input[name='source_ids[]'][value='#{@document.id}']"
    assert_select "form[action='#{study_map_path}'] input[name='source_ids[]'][value='#{second.id}']"
    assert_select ".study-map-list", text: /Unselected source/, count: 0
  end
end
