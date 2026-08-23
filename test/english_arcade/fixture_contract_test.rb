require "test_helper"
require_relative "english_arcade_fixture_validator"

class EnglishArcadeFixtureContractTest < ActiveSupport::TestCase
  setup do
    @fixture = EnglishArcade::FixtureValidator.load_fixture
  end

  test "ships exactly eight C2 interview target packs with twelve items each" do
    validator = EnglishArcade::FixtureValidator.new(@fixture)

    assert_predicate validator, :valid?, validator.errors.join("\n")
    assert_equal EnglishArcade::FixtureValidator::TARGET_KEYS.sort, @fixture.fetch("targets").map { |target| target.fetch("key") }.sort
    assert @fixture.fetch("targets").all? { |target| target.fetch("items").length >= 12 }
  end

  test "each item has a closed-book prompt, distractors, feedback, and rephrase path" do
    items = @fixture.fetch("targets").flat_map { |target| target.fetch("items") }

    items.each do |item|
      assert item.fetch("prompt").present?
      assert item.fetch("context").present?
      assert item.fetch("answer").present?
      assert_operator item.fetch("distractors").length, :>=, 2
      assert_equal %w[grammar hedging pragmatics precision register], item.fetch("feedback").keys.sort
      assert item.fetch("rephrase").present?
      assert item.fetch("extension").present?
    end
  end

  test "revealed answers are never part of learner-visible fields" do
    learner_fields = @fixture.fetch("presentation").fetch("learner_fields")
    reveal_fields = @fixture.fetch("presentation").fetch("reveal_fields")

    assert_includes reveal_fields, "answer"
    assert_not_includes learner_fields, "answer"
    assert_not_includes learner_fields, "solution"

    @fixture.fetch("targets").each do |target|
      target.fetch("items").each do |item|
        public_text = %w[prompt context rephrase extension].map { |key| item.fetch(key) } + item.fetch("distractors")
        refute public_text.join(" ").downcase.include?(item.fetch("answer").downcase), item.fetch("id")
      end
    end
  end

  test "validator catches a removed contract field and an answer leak" do
    broken = Marshal.load(Marshal.dump(@fixture))
    item = broken.fetch("targets").first.fetch("items").first
    item.delete("rephrase")
    item["context"] = item.fetch("answer")

    validator = EnglishArcade::FixtureValidator.new(broken)

    assert_not validator.valid?
    assert validator.errors.any? { |error| error.include?("rephrase") }
    assert validator.errors.any? { |error| error.include?("answer leaks") }
  end

  test "validator rejects a direct mastery transition" do
    broken = Marshal.load(Marshal.dump(@fixture))
    broken.fetch("state_machine").fetch("transitions") << %w[feedback mastered]

    validator = EnglishArcade::FixtureValidator.new(broken)

    assert_not validator.valid?
    assert validator.errors.any? { |error| error.include?("mastery must only follow reattempt") }
  end

  test "learning loop encodes Feynman, Black Box, Leitner, and delayed mastery" do
    learning_loop = @fixture.fetch("learning_loop")

    assert_equal %w[active_recall feynman black_box leitner reattempt], learning_loop.fetch("stages")
    assert_equal({ 1 => 1, 2 => 2, 3 => 4, 4 => 7, 5 => 14 }, learning_loop.fetch("leitner").fetch("intervals_days").transform_keys(&:to_i))
    assert_equal 1, learning_loop.fetch("leitner").fetch("wrong_answer_box")
    assert_operator learning_loop.fetch("mastery").fetch("score_at_least"), :>=, 8
    assert_operator learning_loop.fetch("mastery").fetch("attempts"), :>=, 2
    assert_operator learning_loop.fetch("mastery").fetch("separation_days"), :>=, 7
  end

  test "state machine prevents skipping recall and feedback before mastery" do
    state_machine = @fixture.fetch("state_machine")
    transitions = state_machine.fetch("transitions").map { |edge| edge.map(&:to_s) }

    assert_includes transitions, %w[idle active_recall]
    assert_includes transitions, %w[active_recall feynman]
    assert_includes transitions, %w[feynman feedback]
    assert_includes transitions, %w[feedback scheduled]
    assert_includes transitions, %w[feedback black_box]
    assert_includes transitions, %w[scheduled reattempt]
    assert_includes transitions, %w[reattempt mastered]
    assert_includes state_machine.fetch("forbidden_transitions"), %w[idle mastered]
    assert_includes state_machine.fetch("forbidden_transitions"), %w[active_recall mastered]
    assert_equal [ "mastered" ], state_machine.fetch("terminal_states")
  end
end
