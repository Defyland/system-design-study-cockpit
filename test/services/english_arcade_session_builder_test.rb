require "test_helper"
require "yaml"

class EnglishArcadeSessionBuilderTest < ActiveSupport::TestCase
  setup do
    EnglishArcadeCard.delete_all
    EnglishArcadeAttempt.delete_all
    EnglishArcadeSession.delete_all
    @builder = EnglishArcadeSessionBuilder.new(clock: -> { Time.zone.local(2026, 8, 23, 9, 0, 0) })
  end

  test "exposes every target including mixed and interview modes" do
    assert_equal EnglishArcade::Schema::TARGETS + %w[mixed interview], @builder.targets.keys
    assert_equal EnglishArcadeSession::TARGETS, @builder.targets.keys
    assert_equal EnglishArcadeSession::TARGETS, Content::EnglishArcadeImporter::TARGETS + %w[mixed interview]
    assert_equal EnglishArcade::Schema::TARGETS, ContentReadinessReport::ARCADE_TARGETS
    assert_equal %w[daily timed_30 timed_45], @builder.modes.keys
    assert_equal 1_800, @builder.modes.fetch("timed_30").fetch(:duration_seconds)
    assert_equal 2_700, @builder.modes.fetch("timed_45").fetch(:duration_seconds)
  end

  test "keeps experience targets launchable and mixed plans include each canonical experience pack" do
    %w[career rails_experience go_experience elixir_experience].each do |target|
      assert_equal target, @builder.normalize_target(@builder.targets.fetch(target).fetch(:label))
      assert_operator @builder.call(target: target, learner_key: "experience", limit: 1).cards.size, :>, 0
    end

    mixed_targets = @builder.call(target: "mixed", learner_key: "experience", limit: 176).cards.map(&:target).uniq
    assert_equal EnglishArcade::Schema::CANONICAL_TARGETS.sort, mixed_targets.sort
  end

  test "interview mode uses the bounded user-supplied resume profile" do
    plan = @builder.call(target: "interview", learner_key: "resume-interview", limit: 12, persist_schedules: false)

    assert_equal EnglishArcadeResumeInterviewProfile::CARD_KEYS, plan.cards.map(&:key)
    assert_equal [ "career" ], plan.cards.map(&:target).uniq
    assert_equal 12, plan.cards.map(&:prompt).uniq.size
    assert_equal 4, plan.cards.first.options.size
    visible = plan.cards.flat_map do |card|
      [ card.prompt, card.context, card.answer_text, card.response_versions.values, card.sources, card.provenance ].flatten
    end.to_json
    assert_includes visible, "100 million requests per day"
    assert_includes visible, "eight microfrontends"
    assert_includes visible, "Samsung Tizen"
    assert_includes visible, "transactional outbox"
    assert_includes visible, "four critical services"
    assert_includes visible, "twenty-five minutes to eight minutes"
    assert_includes visible, "seven seconds to two seconds"
    assert_includes visible, "Yellow Team"
    assert_includes visible, "2.5 million clients"
    assert_includes visible, "allan_flavio_resume_fullstack_v3.pdf"
    assert_includes visible, "allan_flavio_resume_smarttv.pdf"
    assert_includes visible, "allan_flavio_resume_frontend.pdf"
    refute_includes visible, "/Users/"
    refute_match(/resume PDF is absent/i, visible)
    refute_match(/self-reported|needs? confirmation|confirmation required/i, visible)
    refute_match(/@|linkedin\.com|\+\d{2}/i, visible)
    assert plan.cards.all? { |card| card.provenance.fetch("files").all? { |file| file.fetch("identifier_kind") == "sha256" } }
    assert plan.cards.all? { |card| card.provenance.fetch("confirmation_required").empty? }
    refute_match(/\bHTML\b|\bCSS\b|box model|semantic markup/i, plan.cards.map(&:prompt).join(" "))
  end

  test "resume interview decoration does not mutate the canonical career pack" do
    interview = @builder.card_for(
      target: "interview",
      card_key: "career-01-a-60-to-90-second-introduction"
    )
    career = @builder.card_for(
      target: "career",
      card_key: "career-01-a-60-to-90-second-introduction"
    )

    assert_includes interview.prompt, "backend scale"
    assert_equal "Tell me about yourself in a minute or so.", career.prompt
    refute_equal interview.answer_text, career.answer_text
  end

  test "builds a bounded mixed plan and persists due cards without answer metadata" do
    plan = @builder.call(target: "mixed", mode: "daily", learner_key: "study")

    assert_equal 5, plan.cards.length
    assert plan.cards.map(&:target).uniq.length > 1
    assert_operator EnglishArcadeCard.where(learner_key: "study").count, :>=, 64

    snapshot = @builder.prompt_snapshot(plan.cards.first)
    refute snapshot.key?("correct_choice"), "the server must not serialize the answer key into the prompt snapshot"
    refute snapshot.key?("answer_text"), "the answer text belongs in feedback after commit"
    refute snapshot.values.any? { |value| value.is_a?(String) && value.include?("answer_key") }
  end

  test "grades a choice without leaking feedback until the final reveal" do
    card = @builder.call(target: "ruby", learner_key: "study", limit: 1).cards.first
    grade = @builder.grade(card: card, answer_choice: card.correct_choice)

    assert grade.correct
    assert_equal card.answer_text, grade.feedback.fetch("answer")
    assert_equal "answer-within-contract", grade.diagnostic_evidence.fetch("signal")
  end

  test "keeps all evidence for reveal feedback but excludes it from the closed prompt" do
    card = @builder.card_for(target: "go_experience", card_key: "go_experience-01-backend-service-template-memory-idempotency")
    snapshot = @builder.prompt_snapshot(card)
    grade = @builder.grade(card: card, answer_choice: card.correct_choice)

    %w[source sources provenance].each { |key| refute snapshot.key?(key), "#{key} must stay out of prompt_snapshot" }
    assert_equal card.sources, grade.feedback.fetch("sources")
    assert_equal card.provenance, grade.feedback.fetch("provenance")
  end

  test "uses a stable randomized deck order for each normal session" do
    seeded_cards = @builder.call(target: "rails", learner_key: "study", limit: 20, persist_schedules: true).cards
    EnglishArcadeCard.where(learner_key: "study", target: "rails").order(:card_key).each_with_index do |schedule, index|
      schedule.update!(due_on: Date.current - index.days)
    end
    first_session = EnglishArcadeSession.create!(
      learner_key: "study", target: "rails", mode: "daily", duration_seconds: 600,
      started_at: Time.current, metadata: { "deck_seed" => "first-session-seed" }
    )
    second_session = EnglishArcadeSession.create!(
      learner_key: "study", target: "rails", mode: "daily", duration_seconds: 600,
      started_at: Time.current, metadata: { "deck_seed" => "second-session-seed" }
    )

    first_order = @builder.call(target: "rails", learner_key: "study", session: first_session, limit: 20, persist_schedules: false).cards.map(&:key)
    repeated_order = @builder.call(target: "rails", learner_key: "study", session: first_session, limit: 20, persist_schedules: false).cards.map(&:key)
    second_order = @builder.call(target: "rails", learner_key: "study", session: second_session, limit: 20, persist_schedules: false).cards.map(&:key)

    assert_equal first_order, repeated_order
    assert_equal first_order.sort, second_order.sort
    assert_equal seeded_cards.map(&:key).sort_by { |key| Digest::SHA256.hexdigest("first-session-seed:#{key}") }, first_order
    refute_equal first_order, second_order
  end

  test "keeps the canonical answer key attached when choices are rotated" do
    card = @builder.card_for(target: "react", card_key: "react-01-state-ownership")
    correct = card.options.find { |choice| choice.id == card.correct_choice }

    assert_equal card.answer_text, correct.text
    assert @builder.grade(card: card, answer_choice: card.correct_choice).correct
  end

  test "projects authored response versions and option guidance for guided study" do
    card = @builder.card_for(target: "career", card_key: "career-01-a-60-to-90-second-introduction")

    assert_equal %w[short medium deep], card.response_versions.keys
    assert_equal card.answer_text, card.response_versions.fetch("medium")
    best = card.option_guides.values.find { |guide| guide.fetch("best") }
    distractor = card.option_guides.values.find { |guide| guide.key?("explanation") }
    assert best, "the authored best option should be marked for guided study"
    assert distractor, "an authored distractor explanation should be available"
    assert_predicate distractor.fetch("explanation"), :present?
  end

  test "uses a replaceable content adapter" do
    adapter = Class.new do
      def self.cards_for(target)
        EnglishArcadeSessionBuilder::FixtureAdapter.cards_for("salesforce").first(2).each_with_index.map do |card, index|
          card.merge(target: target, key: "adapter-#{target}-#{index + 1}", source: "opus-adapter-fixture")
        end
      end

      def self.source_name
        "opus-adapter-fixture"
      end
    end
    builder = EnglishArcadeSessionBuilder.new(content: adapter)

    plan = builder.call(target: "dsa", learner_key: "study", limit: 2)

    assert_equal %w[adapter-dsa-1 adapter-dsa-2], plan.cards.map(&:key)
    assert_equal "opus-adapter-fixture", plan.source
  end

  test "public builder fails closed for malformed production packs instead of injecting fixture prompts" do
    mutations = [
      [ "go_experience", "go-experience.yml", "prompt" ],
      [ "dsa", "dsa.yml", "follow_up" ]
    ]
    mutations.each do |target, filename, field|
      pack = YAML.safe_load_file(Rails.root.join("db/seeds/english_arcade/#{filename}"), aliases: false)
      if field == "prompt"
        pack.fetch("items").first.delete("prompt")
      else
        pack.fetch("items").first.delete("follow_up")
      end
      unavailable = EnglishArcadeSessionBuilder::ContentPackAdapter.send(:validated_packs, { target => pack })

      content = EnglishArcadeSessionBuilder::ContentPackAdapter.new(unavailable, source_name: "invalid-pack")
      builder = EnglishArcadeSessionBuilder.new(content: content)
      assert_empty builder.call(target: target, learner_key: "malformed", limit: 1).cards, "#{target} must be unavailable"
    end
  end

  test "an unexpected production loader error cannot resurrect canonical fixture cards" do
    adapter = EnglishArcadeSessionBuilder::ContentPackAdapter
    original = adapter.method(:load_pack_directory)
    adapter.define_singleton_method(:load_pack_directory) { raise "loader unavailable" }
    begin
      builder = EnglishArcadeSessionBuilder.new
      EnglishArcade::Schema::CANONICAL_TARGETS.each do |target|
        assert_empty builder.call(target: target, learner_key: "loader-error", limit: 1).cards, "#{target} must remain unavailable"
      end
    ensure
      adapter.define_singleton_method(:load_pack_directory, original)
    end
  end

  test "required mock cards advance only after a revealed scheduled attempt" do
    session = EnglishArcadeSession.create!(
      learner_key: "study",
      target: "general",
      mode: "timed_30",
      duration_seconds: 1_800,
      started_at: Time.current,
      metadata: { "required_card_keys" => EnglishArcadeCurriculum::GENERAL_FINAL_MOCK_ITEM_IDS }
    )
    session.english_arcade_attempts.create!(
      learner_key: "study", target: "general", card_key: "general-06-star-conflict",
      attempt_kind: "initial", typed_answer: "A sufficiently detailed committed answer for the first required mock card.",
      correct: true, feedback_revealed: false, state: "feynman", quality_score: 0,
      box_before: 1, box_after: 1, answered_at: Time.current, diagnostic_evidence: {}
    )

    plan = @builder.call(target: "general", mode: "timed_30", learner_key: "study", session: session)
    assert_equal EnglishArcadeCurriculum::GENERAL_FINAL_MOCK_ITEM_IDS, plan.cards.map(&:key)

    session.english_arcade_attempts.first.update!(feedback_revealed: true, state: "revealed")
    plan = @builder.call(target: "general", mode: "timed_30", learner_key: "study", session: session)

    assert_equal EnglishArcadeCurriculum::GENERAL_FINAL_MOCK_ITEM_IDS.drop(1), plan.cards.map(&:key)
  end
end
