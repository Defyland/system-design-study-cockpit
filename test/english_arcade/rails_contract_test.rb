require "test_helper"
require_relative "english_arcade_fixture_validator"

class EnglishArcadeRailsContractTest < ActionDispatch::IntegrationTest
  FakeSource = Struct.new(:documents, :curriculum)

  setup do
    reset_study_tables!
    EnglishArcadeAttempt.delete_all
    EnglishArcadeCard.delete_all
    EnglishArcadeSession.delete_all
    @fixture = EnglishArcade::FixtureValidator.load_fixture
    @item = @fixture.fetch("targets").first.fetch("items").first
  end

  test "imports a target item as a persisted checkpoint and makes it searchable" do
    source = FakeSource.new([
      {
        kind: "interview_story_bank",
        source_path: "english-arcade/packs/dsa.md",
        body_markdown: <<~MARKDOWN
          # DSA C2 Arcade

          ## Active Recall

          - `Pergunta`: #{@item.fetch("prompt")}
          - `Resposta curta`: #{@item.fetch("answer")}
          - `Troque por isto`: #{@item.fetch("rephrase")}
        MARKDOWN
      }
    ], nil)

    document = Content::Importer.new(source: source).call.first

    assert_predicate document, :persisted?
    assert_equal "interview_story_bank", document.kind
    assert_equal 1, document.checkpoints.count
    assert_equal @item.fetch("answer"), document.checkpoints.first.good_answer
    assert_predicate document.study_progress, :not_started?

    imported_again = Content::Importer.new(source: source).call.first
    assert_equal document.id, imported_again.id
    assert_equal [ document.checkpoints.first.id ], imported_again.checkpoints.pluck(:id)

    get search_path(q: "sliding-window")

    assert_response :success
    assert_includes response.body, document.title
  end

  test "registers the English Arcade launcher route" do
    get "/english-arcade"

    assert_response :success
    assert_select "section.english-arcade[data-controller='english-arcade']"
    assert_select "form[action*='english-arcade'] [role='radiogroup'][aria-label='Interview target']"
    assert_no_match(/class="arcade-answer"/, response.body)
    assert_not_includes response.body, "Answer after attempt"
  end

  test "persists target preference, closed-book attempt, and reflection data" do
    document = create_pack_document(kind: "side_track_overview")
    checkpoint = document.checkpoints.create!(
      position: 1,
      source_label: "Active Recall",
      prompt: @item.fetch("prompt"),
      good_answer: @item.fetch("answer"),
      correction: @item.fetch("feedback").fetch("precision")
    )
    document.update!(metadata: document.metadata.merge(
      "target_key" => "dsa",
      "adaptive_level" => "c2",
      "saved_target_at" => Time.current.iso8601
    ))

    attempt = RecordCheckpointAttempt.call(
      checkpoint: checkpoint,
      attributes: {
        result: "missed",
        prediction_text: "I would begin with an assumption.",
        decision_sentence: "I would state the invariant before choosing the loop.",
        confidence: "low"
      }
    )
    reflection = LearningRecord.create!(
      study_document: document,
      cue: "Feynman",
      insight: "The invariant explains why the window remains valid.",
      unlocks: "Black Box: I had skipped the boundary condition."
    )

    reloaded = document.reload
    assert_equal "dsa", reloaded.metadata.fetch("target_key")
    assert_equal "c2", reloaded.metadata.fetch("adaptive_level")
    assert_equal "missed", attempt.reload.result
    assert_equal "Black Box: I had skipped the boundary condition.", reflection.reload.unlocks
    assert_equal [ 1, 3, 7, 14, 30 ], document.review_schedules.order(:interval_days).pluck(:interval_days)
  end

  test "enforces Leitner intervals and delayed two-variant mastery" do
    at = Time.zone.local(2026, 8, 23, 9, 0, 0)
    card = EnglishArcadeCard.create!(
      learner_key: "english-arcade-test",
      target: "dsa",
      card_key: "dsa-contract-1",
      due_on: at.to_date
    )

    card.update!(box: 4, interval_days: 7)
    card.record!(correct: false, at: at)
    assert_equal 1, card.box
    assert_equal 1, card.interval_days
    assert_equal at.to_date + 1.day, card.due_on

    card.update!(box: 4, interval_days: 7, due_on: at.to_date)
    card.record!(correct: true, at: at)
    assert_equal 5, card.box
    assert_equal 14, card.interval_days
    assert_equal at.to_date + 14.days, card.due_on

    session = EnglishArcadeSession.create!(
      learner_key: "english-arcade-test",
      target: "dsa",
      mode: "daily",
      status: "active",
      duration_seconds: 600,
      started_at: at,
      expires_at: at + 600.seconds
    )
    create_mastery_attempt(session, "initial", at, 9)
    create_mastery_attempt(session, "rephrase", at + 7.days, 8)

    assert card.mastered?
    assert_equal true, card.mastery_progress.fetch("mastered")
  end

  test "prompt snapshots omit the answer key and reveal-only fields" do
    builder = EnglishArcadeSessionBuilder.new(content: EnglishArcadeSessionBuilder::FixtureAdapter)
    card = builder.call(target: "dsa", learner_key: "english-arcade-test", limit: 1).cards.first
    snapshot = builder.prompt_snapshot(card)

    assert_equal %w[context extension_prompt key options prompt rephrase_prompt source tags target target_label].sort, snapshot.keys.sort
    refute snapshot.key?("answer_text")
    refute snapshot.key?("correct_choice")
    refute snapshot.values.any? { |value| value.is_a?(String) && value.include?("answer_key") }
  end

  test "does not render a checkpoint answer in the learner document view" do
    document = create_pack_document
    document.study_blocks.create!(
      position: 1,
      kind: "paragraph",
      content_markdown: @item.fetch("prompt")
    )
    document.checkpoints.create!(
      position: 1,
      source_label: "Active Recall",
      prompt: @item.fetch("prompt"),
      good_answer: @item.fetch("answer")
    )

    get library_document_path(kind: document.kind, slug: document.slug)

    assert_response :success
    assert_includes response.body, @item.fetch("prompt")
    assert_not_includes response.body, @item.fetch("answer")
  end

  test "health endpoint exposes content readiness fields used by the release gate" do
    StudyDocument.create!(
      kind: "side_track_overview",
      slug: "backend-interview-foundations",
      title: "Backend Interview Foundations",
      source_path: "areas/01-metodo-e-entrevistas/backend-interview-foundations/README.md",
      position: 0,
      body_markdown: "# Backend Interview Foundations",
      body_checksum: "english-arcade-health"
    )
    ContentSyncRun.create!(
      source_mode: "filesystem",
      source_location: "system-design-estudos",
      status: "succeeded",
      document_count: 1,
      started_at: 1.minute.ago,
      finished_at: Time.current
    )

    get health_content_path

    assert_response :success
    payload = JSON.parse(response.body)
    %w[status study_documents content_bootstrapped latest_sync_status].each do |key|
      assert payload.key?(key), "missing health field #{key}"
    end
    assert_equal true, payload.fetch("content_bootstrapped")
  end

  private

  def create_pack_document(kind: "reference_document")
    StudyDocument.create!(
      kind: kind,
      slug: "english-arcade-packs-dsa-01",
      title: "English C2 Arcade DSA",
      source_path: "english-arcade/packs/dsa.md",
      position: 0,
      body_markdown: "# English C2 Arcade DSA\n\n#{@item.fetch("prompt")}",
      body_checksum: "english-arcade-dsa-01",
      metadata: { "target_key" => "dsa", "source_attribution" => "english-arcade" }
    )
  end

  def create_mastery_attempt(session, variant_key, answered_at, quality_score)
    EnglishArcadeAttempt.create!(
      english_arcade_session: session,
      learner_key: "english-arcade-test",
      target: "dsa",
      card_key: "dsa-contract-1",
      attempt_kind: variant_key == "initial" ? "initial" : "rephrase",
      variant_key: variant_key,
      answer_choice: "a",
      correct: true,
      feedback_revealed: true,
      state: "revealed",
      quality_score: quality_score,
      answered_at: answered_at
    )
  end
end
