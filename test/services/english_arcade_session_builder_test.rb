require "test_helper"

class EnglishArcadeSessionBuilderTest < ActiveSupport::TestCase
  setup do
    EnglishArcadeCard.delete_all
    EnglishArcadeAttempt.delete_all
    EnglishArcadeSession.delete_all
    @builder = EnglishArcadeSessionBuilder.new(clock: -> { Time.zone.local(2026, 8, 23, 9, 0, 0) })
  end

  test "exposes every target including mixed and interview modes" do
    assert_equal %w[dsa ruby rails react golang elixir salesforce system_design mixed interview], @builder.targets.keys
    assert_equal %w[daily timed_45], @builder.modes.keys
    assert_equal 2_700, @builder.modes.fetch("timed_45").fetch(:duration_seconds)
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

  test "keeps the canonical answer key attached when choices are rotated" do
    card = @builder.card_for(target: "react", card_key: "react-01-state-ownership")
    correct = card.options.find { |choice| choice.id == card.correct_choice }

    assert_equal card.answer_text, correct.text
    assert @builder.grade(card: card, answer_choice: card.correct_choice).correct
  end

  test "uses a replaceable content adapter" do
    adapter = Class.new do
      def self.cards_for(target)
        EnglishArcadeSessionBuilder::FixtureAdapter.cards_for(target).first(2).map do |card|
          card.merge(key: "adapter-#{card.fetch(:key)}", source: "opus-adapter-fixture")
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
end
