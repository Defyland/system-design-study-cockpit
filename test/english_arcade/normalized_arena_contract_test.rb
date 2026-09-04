# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../config/environment"
require_relative "../../app/services/english_arcade_session_builder"
require_relative "../../lib/english_arcade/corpus_index"
require_relative "../../lib/english_arcade/exercise_factory"
require_relative "../../lib/english_arcade/exercise_grader"

class NormalizedArenaContractTest < Minitest::Test
  def test_factory_and_grader_accept_the_session_builders_normalized_card_contract
    builder = EnglishArcadeSessionBuilder.new
    card = builder.cards_for("golang").find { |candidate| candidate.fetch(:key) == "golang-01-interface-placement" }
    index = EnglishArcade::CorpusIndex.new(builder.cards_for("mixed"))
    factory = EnglishArcade::ExerciseFactory.new(corpus_index: index)
    exercise = factory.build(card, stage: :recognize, content_version: card.fetch(:content_version))
    correct = exercise.dig("payload", "options").find { |option| option.fetch("text") == card.fetch(:answer_text) }
    grade = EnglishArcade::ExerciseGrader.grade(exercise, item: card, response: correct.fetch("id"), response_ms: 5_000)

    assert_equal "golang-01-interface-placement", exercise.fetch("card_key")
    assert_equal true, grade.fetch("correct")
    assert_equal 3, grade.fetch("rating")
  end
end
