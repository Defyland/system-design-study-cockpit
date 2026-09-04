# frozen_string_literal: true

require_relative "arcade_test_helper"

class EnglishArcadeTextToolsTest < Minitest::Test
  def test_normalizes_and_calculates_word_lcs
    assert_equal "i would test the boundary", EnglishArcade::TextTools.normalize("I would test the boundary.")
    assert_equal 4, EnglishArcade::TextTools.lcs_length("I would test it", "I would not test it")
    assert_in_delta 0.8, EnglishArcade::TextTools.similarity("I would test it", "I would not test it"), 0.001
  end

  def test_diff_segments_preserve_transfer_phrase
    distractor = sample_item.fetch("distractors").find { |choice| choice.fetch("trap") == "grammar" }
    segments = EnglishArcade::TextTools.diff_segments(sample_item.fetch("best_answer"), distractor.fetch("text"))

    assert segments.any? { |entry| entry.fetch(:best).include?("as i can make it") }
    assert segments.any? { |entry| entry.fetch(:alternative).include?("possible") }
  end

  def test_clause_chunks_are_reconstructable
    chunks = EnglishArcade::TextTools.clause_chunks(sample_item.fetch("best_answer"))

    assert_operator chunks.length, :>=, 3
    assert_equal EnglishArcade::TextTools.normalize(sample_item.fetch("best_answer")), EnglishArcade::TextTools.normalize(chunks.join(" "))
  end

  def test_display_tokens_keep_technical_punctuation_and_mark_crossing_spans
    answer = "The client sends POST /payments with an idempotency key."

    assert_equal [ "The", "client", "sends", "POST", "/payments", "with", "an", "idempotency", "key." ], EnglishArcade::TextTools.display_tokens(answer)
    refute EnglishArcade::TextTools.span_crosses_punctuation?(answer, 3, 1)
    assert EnglishArcade::TextTools.span_crosses_punctuation?(answer, 3, 2)
  end

  def test_clause_chunks_merge_a_short_leading_sentence
    chunks = EnglishArcade::TextTools.clause_chunks("Sure. I would state the invariant first, then test a counterexample.")

    assert_operator EnglishArcade::TextTools.word_count(chunks.first), :>=, 4
    assert_equal "sure i would state the invariant first then test a counterexample", EnglishArcade::TextTools.normalize(chunks.join(" "))
  end
end
