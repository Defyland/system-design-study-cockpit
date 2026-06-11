require "application_system_test_case"

class StudyFlowTest < ApplicationSystemTestCase
  setup do
    MisconceptionEvent.delete_all
    LearningRecord.delete_all
    StudyMission.delete_all
    SimulationAttempt.delete_all
    Reminder.delete_all
    StudyDocument.destroy_all
  end

  test "student opens a chapter and reveals checkpoint feedback" do
    document = StudyDocument.create!(
      kind: "chapter",
      slug: "chapter-01-test",
      title: "Chapter 01 - Test",
      source_path: "chapters/chapter-01-test.md",
      position: 1,
      body_markdown: "# Chapter 01 - Test",
      body_checksum: "abc"
    )
    document.create_study_progress!
    document.study_blocks.create!(position: 1, kind: "paragraph", content_markdown: "Um paragrafo de estudo.")
    document.study_blocks.create!(position: 2, kind: "paragraph", content_markdown: "Outro paragrafo.")
    document.study_blocks.create!(position: 3, kind: "paragraph", content_markdown: "Terceiro paragrafo.")
    document.checkpoints.create!(
      position: 1,
      source_label: "Fixacao",
      prompt: "Qual requisito vem primeiro?",
      good_answer: "O requisito real.",
      bad_answer: "A ferramenta.",
      correction: "Questione antes de escolher."
    )

    visit root_path
    click_link "Abrir chapter"
    fill_in "Antes de revelar: qual e seu palpite?", with: "Eu questionaria o requisito primeiro."
    fill_in "Complete a frase tecnica", with: "Eu usaria simplicidade quando o requisito ainda nao foi provado."
    choose "Medium"
    click_button "Revelar resposta e correcao"

    assert_text "O requisito real."
    assert_text "A ferramenta."
    click_button "Missed"

    assert_text "Checkpoint registrado."
    assert_equal 1, MisconceptionEvent.count
  end

  test "student runs a simulation and stores a decision" do
    StudyDocument.create!(
      kind: "simulation_lab",
      slug: "load-balancer",
      title: "Load Balancer Lab",
      source_path: "simulation-labs/load-balancer.md",
      position: 0,
      body_markdown: "# Load Balancer Lab",
      body_checksum: "sim-lb"
    )

    visit simulations_path
    click_link "Simular", match: :first

    assert_text "Load Balancer Capacity"
    assert_text "Utilizacao"
    fill_in "Resposta oral curta", with: "Eu limitaria o tenant quente e observaria erro."
    choose "Arriscado, preciso conter"
    click_button "Salvar tentativa"

    assert_text "Tentativa registrada."
    assert_text "Arriscado"
    assert_equal 1, SimulationAttempt.where(simulation_slug: "load-balancer").count
    assert_equal 1, Reminder.where(source_slug: "load-balancer").count
  end

  test "student sets a side track mission and stores a learning record" do
    overview = StudyDocument.create!(
      kind: "side_track_overview",
      slug: "llm-foundations",
      title: "LLM Foundations",
      source_path: "areas/08-sistemas-ia/llm-foundations/README.md",
      position: 0,
      body_markdown: "# LLM Foundations",
      body_checksum: "llm-foundations",
      metadata: {
        "side_track_id" => "llm-foundations",
        "side_track_area_title" => "Sistemas de IA",
        "chapter_count" => 1
      }
    )
    overview.create_study_progress!
    overview.study_blocks.create!(position: 1, kind: "paragraph", content_markdown: "Trilha paralela.")

    chapter = StudyDocument.create!(
      kind: "side_track_chapter",
      slug: "llm-foundations-01-tokens",
      title: "Tokens, Embeddings and Training Windows",
      source_path: "areas/08-sistemas-ia/llm-foundations/chapters/01-tokens-embeddings-and-training-windows.md",
      position: 1,
      body_markdown: "# Tokens, Embeddings and Training Windows",
      body_checksum: "llm-foundations-01",
      metadata: {
        "side_track_id" => "llm-foundations",
        "study_order" => "1/1",
        "bridge_topics" => [ "areas/08-sistemas-ia/topics/token-cost.md" ],
        "review_card_path" => "areas/08-sistemas-ia/llm-foundations/reviews/cards/01-tokens-embeddings-and-training-windows.md"
      }
    )
    chapter.create_study_progress!

    review_card = StudyDocument.create!(
      kind: "side_track_review_card",
      slug: "llm-foundations-01-tokens-review",
      title: "Tokens Recall",
      source_path: "areas/08-sistemas-ia/llm-foundations/reviews/cards/01-tokens-embeddings-and-training-windows.md",
      position: 1,
      body_markdown: "# Tokens Recall",
      body_checksum: "llm-foundations-01-review",
      metadata: {
        "side_track_id" => "llm-foundations",
        "chapter_path" => chapter.source_path
      }
    )
    review_card.create_study_progress!

    visit side_track_path("llm-foundations")
    fill_in "Why now", with: "Quero entender modelo o suficiente para nao vender RAG como resposta universal."
    fill_in "Success signal", with: "Consigo explicar tokenizacao, attention e finetuning com consequencia arquitetural."
    click_button "Salvar mission"

    assert_text "Mission salva."
    fill_in "Cue", with: "Token budget nao e detalhe de API."
    fill_in "Insight", with: "Ficou claro por que custo de contexto e serving dependem da estrutura do modelo."
    fill_in "Unlocks", with: "Consigo discutir latencia antes de falar em cache."
    click_button "Salvar learning record"

    assert_text "Learning record salvo."
    assert_text "Token budget nao e detalhe de API."
    assert_equal 1, StudyMission.count
    assert_equal 1, LearningRecord.count
  end
end
