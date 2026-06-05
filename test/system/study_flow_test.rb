require "application_system_test_case"

class StudyFlowTest < ApplicationSystemTestCase
  setup do
    MisconceptionEvent.delete_all
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
end
