# frozen_string_literal: true

require_relative "arcade_test_helper"
require "json"

class EnglishArcadeExerciseFactoryTest < Minitest::Test
  FORBIDDEN = %w[reveal best_answer correct why_wrong pt_help sources provenance critical_thinking black_box variants].freeze

  def test_materialization_is_deterministic_and_has_no_initial_leaks
    first = factory.build(sample_item, stage: :recognize, slot: 0)
    second = factory.build(sample_item, stage: :recognize, slot: 0)
    boss = factory.build(sample_item, stage: :recognize, slot: 0, boss: true)

    assert_equal first, second
    refute_equal first.fetch("exercise_id"), boss.fetch("exercise_id")
    assert_empty deep_keys(first) & FORBIDDEN
    refute_includes JSON.generate(first), sample_item.fetch("feedback").fetch("grammar")
  end

  def test_cloze_and_rebuild_cover_every_canonical_item
    canonical_items.each do |item|
      assert factory.supported?(item, stage: :cloze), item.fetch("id")

      cloze = factory.build(item, stage: :cloze)
      blanks = cloze.dig("payload", "blanks")
      assert_operator blanks.length, :>=, 2, item.fetch("id")
      blanks.each do |blank|
        if blank.fetch("input_mode") == "typed"
          assert_empty blank.fetch("chips"), item.fetch("id")
        else
          assert_operator blank.fetch("chips").length, :>=, 2, item.fetch("id")
          assert_operator blank.fetch("chips").length, :<=, 4, item.fetch("id")
        end
        assert_equal blank.fetch("chips").length, blank.fetch("chips").map { |chip| EnglishArcade::TextTools.normalize(chip) }.uniq.length, item.fetch("id")
        assert blank.fetch("chips").all? { |chip| EnglishArcade::TextTools.word_count(chip) == blank.fetch("length") }, item.fetch("id")
        expected = EnglishArcade::TextTools.words(item.fetch("best_answer"))[blank.fetch("start"), blank.fetch("length")].join(" ")
        authored = item.fetch("distractors").flat_map do |choice|
          EnglishArcade::TextTools.diff_segments(item.fetch("best_answer"), choice.fetch("text")).filter_map do |segment|
            segment[:alternative] if segment[:start] == blank.fetch("start") && segment[:length] == blank.fetch("length")
          end
        end
        blank.fetch("chips").reject { |chip| EnglishArcade::TextTools.normalize(chip) == EnglishArcade::TextTools.normalize(expected) }.each do |chip|
          assert_includes authored.map { |value| EnglishArcade::TextTools.normalize(value) }, EnglishArcade::TextTools.normalize(chip), item.fetch("id")
        end
        refute EnglishArcade::TextTools.span_crosses_punctuation?(item.fetch("best_answer"), blank.fetch("start"), blank.fetch("length")), item.fetch("id")
      end
      rebuild = factory.build(item, stage: :rebuild)
      assert_operator rebuild.dig("payload", "chunks").length, :>=, 3, item.fetch("id")
    end
  end

  def test_golang_transfer_error_does_not_create_a_wrong_sized_chip
    item = canonical_items.find { |candidate| factory.supported?(candidate, stage: :cloze) }
    cloze = factory.build(item, stage: :cloze)
    chips = cloze.dig("payload", "blanks").flat_map { |blank| blank.fetch("chips") }

    refute_includes chips, "the more small possible"
    assert chips.all? { |chip| EnglishArcade::TextTools.informative_phrase?(chip) }
  end

  def test_cloze_never_samples_unrelated_corpus_fragments
    item = canonical_items.find { |candidate| candidate.fetch("id") == "dsa-01-pattern-naming" }
    cloze = factory.build(item, stage: :cloze)
    chips = cloze.dig("payload", "blanks").flat_map { |blank| blank.fetch("chips") }

    refute_includes chips, "of every"
    refute_includes chips, "the top"
    refute_includes chips, "top of"
  end

  def test_delayed_boilerplate_is_gated_without_rewriting_the_answer
    item = sample_item.merge(
      "variants" => {
        "delayed_variant" => {
          "prompt" => "A later review changes the workload constraint; choose the answer that still holds.",
          "best_answer" => "I would keep the facts that remain supported about Interfaces and state the updated decision rule.",
          "distractors" => [ { "text" => "Keep the initial rule without checking the new evidence." }, { "text" => "Replace the interface with a universal abstraction immediately." } ]
        }
      }
    )

    refute factory.supported?(item, stage: :transfer, slot: 1)
    assert_raises(EnglishArcade::ExerciseFactory::UnsupportedExercise) { factory.build(item, stage: :transfer, slot: 1) }
  end

  def test_reveal_uses_the_active_transfer_variant
    variant = {
      "prompt" => "A follow-up asks which package should own the interface.",
      "best_answer" => "Keep the interface in the consumer package and test the dependency there.",
      "distractors" => [ { "text" => "Define every interface in a shared package.", "why_wrong" => "It widens ownership before the consumer needs it." } ]
    }
    item = sample_item.merge("variants" => { "follow_up" => variant })

    reveal = factory.reveal(item, variant_key: "follow_up", selected_text: "Define every interface in a shared package.")

    assert_equal variant.fetch("best_answer"), reveal.fetch("best_answer")
    assert_equal "It widens ownership before the consumer needs it.", reveal.fetch("why_wrong")
  end

  private

  def deep_keys(value)
    case value
    when Hash then value.flat_map { |key, nested| [ key.to_s, *deep_keys(nested) ] }
    when Array then value.flat_map { |nested| deep_keys(nested) }
    else []
    end
  end
end
