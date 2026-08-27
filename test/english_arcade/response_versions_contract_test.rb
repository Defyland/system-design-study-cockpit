require "test_helper"
require "yaml"
require_relative "../../lib/english_arcade/pack_validator"

class EnglishArcadeResponseVersionsContractTest < ActiveSupport::TestCase
  SHORT = "I would state the supported decision, name its main constraint, and identify the next verification step while keeping uncertainty explicit for this interviewer context."
  MEDIUM = "I would define the decision boundary, state the verified evidence, identify the remaining assumption, compare a credible alternative, explain the main failure mode, and name the smallest verification step before claiming an outcome. I would keep certainty calibrated, preserve supported facts, and revise the recommendation when new evidence changes the constraint, observed behaviour, or confidence. I would also state what remains unknown so the listener can distinguish an informed design choice from a measured result."
  DEEP = "I would begin by framing the decision in terms of the actor, the required outcome, the constraint, and the evidence that is still missing. I would separate verified facts from inferences, state the assumption that makes the recommendation plausible, and compare it with a credible alternative rather than presenting a preferred pattern as universal. Then I would explain the relevant state transition, the failure mode that could invalidate it, and the smallest observation or test that would discriminate between the explanations. I would keep the same thesis and evidence boundary at every depth, describe uncertainty directly, and avoid converting inspectable design reasoning into a claim about ownership, production operation, or measured impact. If new evidence changes the constraint, I would revise the recommendation and say exactly which part of my confidence moved."
  DISTRACTOR_A = (1..250).map { |index| "alternative#{index}" }.join(" ")
  DISTRACTOR_B = (1..250).map { |index| "tradeoff#{index}" }.join(" ")

  test "1.4 items remain valid without response versions and validate them when present" do
    legacy = load_pack("dsa")
    assert_equal "1.4.0", legacy.fetch("contract_version")
    assert_predicate EnglishArcade::PackValidator.new(legacy, strict: true), :valid?

    item = legacy.fetch("items").find { |candidate| medium_word_range.cover?(candidate.fetch("best_answer").split.size) }
    refute_nil item
    item["response_versions"] = response_versions(medium: item.fetch("best_answer"))

    assert_predicate EnglishArcade::PackValidator.new(legacy, strict: true), :valid?
  end

  test "synthetic 1.5 items remain valid without response versions and validate them when present" do
    transition = synthetic_v15_pack
    assert_equal "1.5.0", transition.fetch("contract_version")
    assert_equal "general", transition.fetch("target").fetch("key")
    assert transition.fetch("items").none? { |item| item.key?("response_versions") }
    assert_predicate EnglishArcade::PackValidator.new(transition, strict: true), :valid?

    item = transition.fetch("items").find { |candidate| medium_word_range.cover?(candidate.fetch("best_answer").split.size) }
    refute_nil item
    item["response_versions"] = response_versions(medium: item.fetch("best_answer"))

    assert_predicate EnglishArcade::PackValidator.new(transition, strict: true), :valid?
  end

  test "Career and General 1.6 packs have complete response versions for all 24 items" do
    %w[career general].each do |target|
      pack = load_pack(target)
      assert_equal "1.6.0", pack.fetch("contract_version")
      assert_equal target, pack.fetch("target").fetch("key")
      assert_equal 12, pack.fetch("items").size
      assert_equal 12, pack.fetch("items").count { |item| item.key?("response_versions") }
      assert_predicate EnglishArcade::PackValidator.new(pack, strict: true), :valid?

      pack.fetch("items").each do |item|
        versions = item.fetch("response_versions")
        label = "#{target}/#{item.fetch('id')}"
        assert_equal %w[deep medium short], versions.keys.sort, label
        counts = %w[short medium deep].to_h { |key| [ key, versions.fetch(key).split.size ] }
        %w[short medium deep].each do |key|
          range = EnglishArcade::Schema::RESPONSE_VERSION_WORD_RANGES.fetch(key)
          assert_includes range, counts.fetch(key), "#{label} #{key}"
        end
        assert_operator counts.fetch("short"), :<, counts.fetch("medium"), label
        assert_operator counts.fetch("medium"), :<, counts.fetch("deep"), label
        assert_equal item.fetch("best_answer"), versions.fetch("medium"), label
        assert_inherited_v15_fields(item, label)
      end
    end
  end

  test "contract promotion remains target-scoped" do
    expected_versions = {
      "dsa" => "1.4.0",
      "ruby" => "1.4.0",
      "rails" => "1.4.0",
      "react" => "1.4.0",
      "golang" => "1.4.0",
      "elixir" => "1.4.0",
      "databases" => "1.4.0",
      "general" => "1.6.0",
      "career" => "1.6.0",
      "rails-experience" => "1.6.0",
      "go-experience" => "1.4.0",
      "elixir-experience" => "1.4.0",
      "system-design" => "1.4.0",
      "salesforce" => "1.1.0"
    }

    expected_versions.each do |target, version|
      assert_equal version, load_pack(target).fetch("contract_version"), target
    end
  end

  test "1.6 requires complete response versions while preserving the 1.5 fields" do
    promoted = promoted_pack
    assert_equal "1.6.0", promoted.fetch("contract_version")
    assert_predicate EnglishArcade::PackValidator.new(promoted, strict: true), :valid?

    missing = deep_copy(promoted)
    missing.fetch("items").first.delete("response_versions")
    missing_validator = EnglishArcade::PackValidator.new(missing, strict: true)
    refute_predicate missing_validator, :valid?
    assert_response_version_error(missing_validator, ".response_versions", "Hash", item_id: promoted.fetch("items").first.fetch("id"))
  end

  test "1.6 checks every base distractor independently for length tells" do
    pack = promoted_pack
    item = pack.fetch("items").first
    best_words = normalized_word_count(item.fetch("best_answer"))
    minimum_words = minimum_distractor_words(best_words)
    short_words = minimum_words - 1

    item.fetch("distractors")[0]["text"] = word_sentence(short_words, "short_distractor")
    item.fetch("distractors")[1]["text"] = word_sentence(best_words, "long_distractor")

    validator = EnglishArcade::PackValidator.new(pack, strict: true)

    refute_predicate validator, :valid?
    length_errors = validator.errors.select { |error| error.message.include?("length alone reveals") }
    assert_equal [ "items[0].distractors[0].text" ], length_errors.map(&:path)
    assert_includes length_errors.first.message, "#{short_words} words vs best answer #{best_words}"
    assert_includes length_errors.first.message, "minimum #{minimum_words} words"
    assert_includes length_errors.first.message, "ratio 1.6"
    assert_includes length_errors.first.message, "cap 50"

    transition = synthetic_v15_pack
    transition_item = transition.fetch("items").first
    transition_best_words = normalized_word_count(transition_item.fetch("best_answer"))
    transition_short_words = minimum_distractor_words(transition_best_words) - 1
    transition_item.fetch("distractors")[0]["text"] = word_sentence(transition_short_words, "short_transition")
    transition_item.fetch("distractors")[1]["text"] = word_sentence(transition_best_words, "long_transition")

    assert_predicate EnglishArcade::PackValidator.new(transition, strict: true), :valid?
  end

  test "1.6 obvious-short guard uses normalized word boundaries and the 50-word cap" do
    cases = [
      [ 80, 50, true ],
      [ 79, 49, false ],
      [ 110, 50, true ],
      [ 110, 49, false ]
    ]

    cases.each do |best_words, distractor_words, expected_valid|
      pack = promoted_pack
      item = pack.fetch("items").first
      item["best_answer"] = word_sentence(best_words, "best_answer")
      item["response_versions"] = response_versions(medium: item.fetch("best_answer"))
      item.fetch("distractors")[0]["text"] = mixed_whitespace_sentence(distractor_words, "short_distractor")
      item.fetch("distractors")[1]["text"] = word_sentence(best_words, "long_distractor")

      validator = EnglishArcade::PackValidator.new(pack, strict: true)

      if expected_valid
        assert_predicate validator, :valid?, "#{best_words}/#{distractor_words} should be valid: #{validator.errors.map(&:to_s)}"
      else
        refute_predicate validator, :valid?, "#{best_words}/#{distractor_words} should be rejected"
        assert validator.errors.any? { |error| error.path == "items[0].distractors[0].text" && error.message.include?("length alone reveals") }, validator.errors.map(&:to_s)
      end
    end
  end

  test "General G02 answers stay free of exercise metadata" do
    item = load_pack("general").fetch("items").find { |candidate| candidate.fetch("id") == "general-02-small-talk" }
    refute_nil item

    answers = { "best_answer" => item.fetch("best_answer") }.merge(item.fetch("response_versions"))
    forbidden = [
      /supplied\s+week\s+detail/i,
      /in\s+this\s+exercise/i,
      /the\s+user\s*['’]?\s*s\s+real\s+week/i
    ]

    answers.each do |label, answer|
      forbidden.each do |pattern|
        refute_match pattern, answer, "#{label} must not expose exercise metadata"
      end
    end
  end

  test "1.6 keeps every inherited 1.5 field unconditionally required" do
    inherited_field_mutants = {
      "follow_up.answer_anchors" => ->(item) { item.fetch("follow_up").delete("answer_anchors") },
      "recall.delayed_variant.answer_anchors" => ->(item) { item.fetch("recall").fetch("delayed_variant").delete("answer_anchors") },
      "recall.delayed_variant.reasoning_moves" => ->(item) { item.fetch("recall").fetch("delayed_variant").delete("reasoning_moves") },
      "recall.delayed_variant.reasoning_moves.verify" => ->(item) { item.fetch("recall").fetch("delayed_variant").fetch("reasoning_moves").delete("verify") },
      "critical_thinking.defense_checks" => ->(item) { item.fetch("critical_thinking").delete("defense_checks") }
    }

    inherited_field_mutants.each do |field, mutate|
      pack = deep_copy(promoted_pack)
      item = pack.fetch("items").first
      mutate.call(item)
      validator = EnglishArcade::PackValidator.new(pack, strict: true)

      refute_predicate validator, :valid?, "removing #{field} must invalidate a 1.6 item"
      assert item.key?("response_versions"), "#{field} mutant must retain response_versions"
      assert validator.errors.any? { |error| error.path.include?(field) }, "expected a diagnostic for #{field}: #{validator.errors.map(&:to_s)}"
    end
  end

  test "word boundaries are inclusive and whitespace is ignored when counting" do
    boundary_cases = {
      short_min: [ 20, 50, 100 ],
      short_max: [ 70, 71, 100 ],
      medium_min: [ 20, 50, 100 ],
      medium_max: [ 20, 140, 141 ],
      deep_min: [ 20, 50, 100 ],
      deep_max: [ 20, 50, 260 ]
    }

    boundary_cases.each do |name, (short_words, medium_words, deep_words)|
      pack = promoted_pack
      versions = version_set(short_words: short_words, medium_words: medium_words, deep_words: deep_words)
      versions["short"] = "\n  #{versions.fetch("short")}  \t"
      set_first_response_versions(pack, versions)

      assert_predicate EnglishArcade::PackValidator.new(pack, strict: true), :valid?, "#{name} should be accepted"
    end
  end

  test "values below or above each word range fail with the measured count" do
    invalid_cases = {
      short_below: [ "short", 19, 50, 100 ],
      short_above: [ "short", 71, 72, 100 ],
      medium_below: [ "medium", 20, 49, 100 ],
      medium_above: [ "medium", 20, 141, 142 ],
      deep_below: [ "deep", 20, 50, 99 ],
      deep_above: [ "deep", 20, 50, 261 ]
    }

    invalid_cases.each do |name, (field, short_words, medium_words, deep_words)|
      pack = promoted_pack
      set_first_response_versions(pack, version_set(short_words: short_words, medium_words: medium_words, deep_words: deep_words))
      validator = EnglishArcade::PackValidator.new(pack, strict: true)

      refute_predicate validator, :valid?, "#{name} should be rejected"
      range_error = validator.errors.any? do |error|
        error.path.end_with?(".response_versions.#{field}") && error.message.include?("must contain")
      end
      assert range_error, "#{name} should identify #{field} range"
      expected_count = { "short" => short_words, "medium" => medium_words, "deep" => deep_words }.fetch(field)
      assert validator.errors.any? { |error| error.path.end_with?(".response_versions.#{field}") && error.message.include?("got #{expected_count}") }
    end
  end

  test "nineteen padded words still fail the short minimum" do
    pack = promoted_pack
    versions = version_set(short_words: 19, medium_words: 50, deep_words: 100)
    versions["short"] = " \n\t#{versions.fetch("short")} \n  "
    item_id = set_first_response_versions(pack, versions)
    validator = EnglishArcade::PackValidator.new(pack, strict: true)

    refute_predicate validator, :valid?
    assert_response_version_error(validator, ".response_versions.short", "got 19", item_id: item_id)
  end

  test "Unicode White_Space is normalized for counts and equality" do
    probe = EnglishArcade::PackValidator.new(promoted_pack, strict: true)
    assert_equal "alpha beta gamma", probe.send(:normalize_whitespace, "alpha\u00A0beta\u2003gamma\t\n")
    assert_equal 3, probe.send(:normalized_tokens, "alpha\u00A0beta\u2003gamma\t\n").length

    pack = promoted_pack
    ascii = version_set(short_words: 20, medium_words: 50, deep_words: 100)
    unicode = {
      "short" => mixed_whitespace_sentence(20, "short_version"),
      "medium" => mixed_whitespace_sentence(50, "medium_version"),
      "deep" => mixed_whitespace_sentence(100, "deep_version")
    }
    item = pack.fetch("items").first
    item["best_answer"] = ascii.fetch("medium")
    item["response_versions"] = unicode

    assert_predicate EnglishArcade::PackValidator.new(pack, strict: true), :valid?

    short_nineteen = promoted_pack
    short_item = short_nineteen.fetch("items").first
    short_item["best_answer"] = ascii.fetch("medium")
    short_item["response_versions"] = {
      "short" => "\u00A0\u2003#{mixed_whitespace_sentence(19, "short_version")}\u2003\u00A0",
      "medium" => ascii.fetch("medium"),
      "deep" => mixed_whitespace_sentence(100, "deep_version")
    }
    short_validator = EnglishArcade::PackValidator.new(short_nineteen, strict: true)

    refute_predicate short_validator, :valid?
    assert_response_version_error(short_validator, ".response_versions.short", "got 19", item_id: short_item.fetch("id"))
  end

  test "headings are forbidden only as Unicode-whitespace-prefixed labels" do
    natural = promoted_pack
    natural_versions = {
      "short" => "#{word_sentence(20, "short_version")} The timeout is short: failures surface quickly.",
      "medium" => "#{word_sentence(50, "medium_version")} The timeout is short: failures surface quickly.",
      "deep" => "#{word_sentence(100, "deep_version")} The timeout is short: failures surface quickly."
    }
    set_first_response_versions(natural, natural_versions)
    assert_predicate EnglishArcade::PackValidator.new(natural, strict: true), :valid?

    { "short" => "Short:", "medium" => "Medium\u00A0:", "deep" => "Deep:" }.each do |field, label|
      pack = promoted_pack
      versions = version_set(short_words: 20, medium_words: 50, deep_words: 100)
      versions[field] = "\u00A0\u2003#{label} #{versions.fetch(field)}"
      item_id = set_first_response_versions(pack, versions)
      validator = EnglishArcade::PackValidator.new(pack, strict: true)

      refute_predicate validator, :valid?
      assert_response_version_error(validator, ".response_versions.#{field}", "heading", item_id: item_id)
    end
  end

  test "response diagnostics carry target and safe fallback context" do
    pack = promoted_pack
    item_id = pack.fetch("items").first.fetch("id")
    pack.fetch("items").first.fetch("response_versions")["short"] = word_sentence(19, "short_version")
    validator = EnglishArcade::PackValidator.new(pack, strict: true)
    refute_predicate validator, :valid?
    assert_response_version_error(validator, ".response_versions.short", "got 19", item_id: item_id, target: "career", item_index: "0")

    missing_target = promoted_pack
    fallback_item = missing_target.fetch("items").first
    missing_target["target"] = {}
    fallback_item.fetch("response_versions")["short"] = word_sentence(19, "short_version")
    fallback_validator = EnglishArcade::PackValidator.new(missing_target, strict: true)
    refute_predicate fallback_validator, :valid?
    assert_response_version_error(
      fallback_validator,
      ".response_versions.short",
      "got 19",
      item_id: fallback_item.fetch("id"),
      target: "unknown",
      item_index: "0"
    )

    [ nil, "malformed-target" ].each do |bad_target|
      malformed_target = promoted_pack
      malformed_target["target"] = bad_target
      assert_nothing_raised { EnglishArcade::PackValidator.new(malformed_target, strict: true).valid? }
    end
  end

  test "empty and whitespace-only values fail without a crash" do
    [ "", " \n\t " ].each do |empty_value|
      %w[short medium deep].each do |field|
        pack = promoted_pack
        versions = response_versions(medium: MEDIUM)
        versions[field] = empty_value
        item_id = set_first_response_versions(pack, versions)
        validator = EnglishArcade::PackValidator.new(pack, strict: true)

        refute_predicate validator, :valid?
        assert_response_version_error(validator, ".response_versions.#{field}", "non-empty String", item_id: item_id)
      end
    end
  end

  test "non-Hash response versions and non-string values fail closed" do
    [ 42, "not-a-hash", [], nil ].each do |value|
      pack = promoted_pack
      item = pack.fetch("items").first
      item["response_versions"] = value
      validator = EnglishArcade::PackValidator.new(pack, strict: true)

      refute_predicate validator, :valid?
      assert_response_version_error(validator, ".response_versions", "Hash", item_id: item.fetch("id"))
    end

    { "short" => 42, "medium" => [], "deep" => false }.each do |field, value|
      pack = promoted_pack
      versions = response_versions(medium: MEDIUM)
      versions[field] = value
      item = pack.fetch("items").first
      item["response_versions"] = versions
      item_id = item.fetch("id")
      validator = EnglishArcade::PackValidator.new(pack, strict: true)

      refute_predicate validator, :valid?
      assert_response_version_error(validator, ".response_versions.#{field}", "non-empty String", item_id: item_id)
    end
  end

  test "medium accepts conservative whitespace differences but rejects case and punctuation changes" do
    whitespace = promoted_pack
    whitespace_versions = response_versions(medium: " \n#{MEDIUM}\t ")
    set_first_response_versions(whitespace, whitespace_versions)
    assert_predicate EnglishArcade::PackValidator.new(whitespace, strict: true), :valid?

    [ MEDIUM.upcase, MEDIUM.sub(/\./, "!") ].each do |changed_medium|
      pack = promoted_pack
      item_id = set_first_response_versions(pack, response_versions(medium: MEDIUM))
      pack.fetch("items").first.fetch("response_versions")["medium"] = changed_medium
      validator = EnglishArcade::PackValidator.new(pack, strict: true)

      refute_predicate validator, :valid?
      assert_response_version_error(validator, ".response_versions.medium", "match best_answer", item_id: item_id)
    end
  end

  test "pack and item contract versions must agree" do
    item_mismatch = promoted_pack
    item_id = item_mismatch.fetch("items").first.fetch("id")
    item_mismatch.fetch("items").first["version"] = "1.5.0"
    item_validator = EnglishArcade::PackValidator.new(item_mismatch, strict: true)
    refute_predicate item_validator, :valid?
    version_error = item_validator.errors.find { |error| error.path.end_with?(".version") && error.message.include?("canonical 1.6.0 content must use 1.6.0") }
    refute_nil version_error
    assert_includes version_error.message, "target=career"
    assert_includes version_error.message, "item_index=0"
    assert_includes version_error.message, "item_id=#{item_id}"
    assert_includes version_error.message, "field=version"
    assert_includes version_error.message, "reason="

    pack_mismatch = promoted_pack
    pack_mismatch["contract_version"] = "1.5.0"
    pack_mismatch.fetch("items").first["version"] = "1.6.0"
    pack_validator = EnglishArcade::PackValidator.new(pack_mismatch, strict: true)
    refute_predicate pack_validator, :valid?
    assert pack_validator.errors.any? { |error| error.path.end_with?(".version") && error.message.include?("canonical 1.5.0 content must use 1.5.0") }
  end

  test "Salesforce remains legacy elective and rejects response versions" do
    legacy = load_pack("salesforce")
    assert_equal "1.1.0", legacy.fetch("contract_version")
    assert_includes EnglishArcade::Schema::ELECTIVE_TARGETS, "salesforce"
    refute_includes EnglishArcade::Schema::CANONICAL_TARGETS, "salesforce"
    assert_predicate EnglishArcade::PackValidator.new(legacy, strict: true), :valid?

    item = legacy.fetch("items").first
    item["response_versions"] = response_versions(medium: item.fetch("best_answer"))
    validator = EnglishArcade::PackValidator.new(legacy, strict: true)

    refute_predicate validator, :valid?
    legacy_error = validator.errors.find { |error| error.path == "items[0]" && error.message.include?("unknown keys: response_versions") }
    refute_nil legacy_error
    assert_includes legacy_error.message, "target=salesforce"
    assert_includes legacy_error.message, "item_index=0"
    assert_includes legacy_error.message, "item_id=#{item.fetch("id")}"
    assert_includes legacy_error.message, "field=response_versions"
    assert_includes legacy_error.message, "reason="
  end

  test "response version mutants fail with field-specific diagnostics" do
    missing_key = deep_copy(promoted_pack)
    missing_key.fetch("items").first.fetch("response_versions").delete("short")
    missing_validator = EnglishArcade::PackValidator.new(missing_key, strict: true)
    refute_predicate missing_validator, :valid?
    assert_response_version_error(missing_validator, ".response_versions", "missing keys: short", item_id: missing_key.fetch("items").first.fetch("id"))

    malformed = deep_copy(promoted_pack)
    versions = malformed.fetch("items").first.fetch("response_versions")
    versions["unexpected"] = SHORT
    versions["medium"] = "Medium: #{MEDIUM}"
    versions["deep"] = SHORT
    malformed.fetch("items").first["best_answer"] = MEDIUM

    validator = EnglishArcade::PackValidator.new(malformed, strict: true)
    refute_predicate validator, :valid?
    item_id = malformed.fetch("items").first.fetch("id")
    assert_response_version_error(validator, ".response_versions", "unknown keys: unexpected", item_id: item_id)
    assert_response_version_error(validator, ".response_versions.medium", "heading", item_id: item_id)
    assert_response_version_error(validator, ".response_versions.deep", "100-260 words", item_id: item_id)
    assert_response_version_error(validator, ".response_versions", "word counts must increase strictly", item_id: item_id)

    wrong_type = deep_copy(promoted_pack)
    wrong_type.fetch("items").first.fetch("response_versions")["short"] = []
    type_validator = EnglishArcade::PackValidator.new(wrong_type, strict: true)
    refute_predicate type_validator, :valid?
    assert_response_version_error(type_validator, ".response_versions.short", "non-empty String", item_id: wrong_type.fetch("items").first.fetch("id"))

    mismatch = deep_copy(promoted_pack)
    mismatch.fetch("items").first.fetch("response_versions")["medium"] = MEDIUM.sub("verified evidence", "different evidence")
    mismatch_validator = EnglishArcade::PackValidator.new(mismatch, strict: true)
    refute_predicate mismatch_validator, :valid?
    assert_response_version_error(mismatch_validator, ".response_versions.medium", "match best_answer", item_id: mismatch.fetch("items").first.fetch("id"))
  end

  test "nil members in each collection fail closed with structured errors" do
    %w[items templates cards].each do |collection|
      pack = load_pack("dsa")
      pack[collection] = [ nil ]
      validator = EnglishArcade::PackValidator.new(pack, strict: true)

      assert_nothing_raised { refute_predicate validator, :valid? }
      assert_collection_member_error(validator, collection, 0)
    end
  end

  test "string integer and array members fail closed in every collection" do
    { "items" => "items", "templates" => "templates", "cards" => "cards" }.each do |collection, label|
      [ "malformed-#{label}", 7, [] ].each do |bad_member|
        pack = load_pack("dsa")
        index = pack.fetch(collection).length
        pack.fetch(collection) << bad_member
        validator = EnglishArcade::PackValidator.new(pack, strict: true)

        assert_nothing_raised { refute_predicate validator, :valid? }
        assert_collection_member_error(validator, collection, index)
      end
    end
  end

  test "mixed collections keep validating valid members after a malformed member" do
    items = load_pack("dsa")
    items.fetch("items").first.delete("prompt")
    items.fetch("items").insert(1, nil)
    item_validator = EnglishArcade::PackValidator.new(items, strict: true)
    refute_predicate item_validator, :valid?
    assert_collection_member_error(item_validator, "items", 1)
    assert item_validator.errors.any? { |error| error.path == "items[0].prompt" && error.message.include?("is required") }

    templates = load_pack("dsa")
    templates.fetch("templates").first.delete("steps")
    templates.fetch("templates") << nil
    template_validator = EnglishArcade::PackValidator.new(templates, strict: true)
    refute_predicate template_validator, :valid?
    assert_collection_member_error(template_validator, "templates", 2)
    assert template_validator.errors.any? { |error| error.path == "templates[0].steps" && error.message.include?("ordered steps") }
    refute template_validator.errors.any? { |error| error.path.include?("template") && error.message.include?("not defined") }

    cards = load_pack("dsa")
    cards.fetch("cards").first.delete("front")
    cards.fetch("cards") << nil
    card_validator = EnglishArcade::PackValidator.new(cards, strict: true)
    refute_predicate card_validator, :valid?
    assert_collection_member_error(card_validator, "cards", 3)
    assert card_validator.errors.any? { |error| error.path == "cards[0].front" && error.message.include?("is required") }
  end

  test "non-Array collections retain their existing shape errors" do
    {
      "items" => [ "pack.items", "missing items array" ],
      "templates" => [ "templates", "must be an array" ],
      "cards" => [ "cards", "must be an array" ]
    }.each do |collection, (path, message)|
      pack = load_pack("dsa")
      pack[collection] = "not-an-array"
      validator = EnglishArcade::PackValidator.new(pack, strict: true)

      assert_nothing_raised { refute_predicate validator, :valid? }
      assert validator.errors.any? { |error| error.path == path && error.message.include?(message) }
      assert_collection_shape_error(validator, collection, path: path)
    end
  end

  test "absent collection keys preserve their existing semantics" do
    absent_cases = {
      "templates" => [ true, "templates" ],
      "items" => [ false, "pack.items" ],
      "cards" => [ false, "cards" ]
    }

    absent_cases.each do |collection, (expected_valid, path)|
      pack = load_pack("career")
      pack.delete(collection)
      refute pack.key?(collection), "absence probe should remove #{collection} explicitly"
      validator = EnglishArcade::PackValidator.new(pack, strict: true)

      if expected_valid
        assert_predicate validator, :valid?, "absent #{collection} should retain its current default"
      else
        refute_predicate validator, :valid?, "absent #{collection} should retain its current required shape"
        assert_collection_shape_error(validator, collection, path: path, target: "career")
      end
    end
  end

  test "explicit nil collection keys fail as malformed shapes" do
    {
      "templates" => "templates",
      "items" => "pack.items",
      "cards" => "cards"
    }.each do |collection, path|
      pack = load_pack("career")
      pack[collection] = nil
      validator = EnglishArcade::PackValidator.new(pack, strict: true)

      assert_nothing_raised { refute_predicate validator, :valid? }
      assert_collection_shape_error(validator, collection, path: path, target: "career")
    end
  end

  private

  def load_pack(target)
    YAML.safe_load_file(Rails.root.join("db/seeds/english_arcade/#{target}.yml"), aliases: false)
  end

  def deep_copy(value)
    YAML.safe_load(YAML.dump(value), aliases: false)
  end

  def medium_word_range
    EnglishArcade::Schema::RESPONSE_VERSION_WORD_RANGES.fetch("medium")
  end

  def normalized_word_count(value)
    value.to_s.gsub(/\p{Space}+/, " ").strip.split(" ").length
  end

  def minimum_distractor_words(best_words)
    [ (best_words.fdiv(EnglishArcade::Schema::BEST_ANSWER_TO_DISTRACTOR_WORD_RATIO)).ceil,
      EnglishArcade::Schema::MAX_DISTRACTOR_WORDS_FOR_LENGTH_TELL ].min
  end

  def response_versions(medium:)
    { "short" => SHORT, "medium" => medium, "deep" => DEEP }
  end

  def version_set(short_words:, medium_words:, deep_words:)
    {
      "short" => word_sentence(short_words, "short_version"),
      "medium" => word_sentence(medium_words, "medium_version"),
      "deep" => word_sentence(deep_words, "deep_version")
    }
  end

  def word_sentence(count, prefix)
    Array.new(count) { |index| "#{prefix}_#{index}" }.join(" ")
  end

  def mixed_whitespace_sentence(count, prefix)
    separators = [ " ", "\t", "\n", "\u00A0", "\u2003" ]
    Array.new(count) { |index| "#{prefix}_#{index}" }.each_with_index.map do |token, index|
      index.zero? ? token : "#{separators[(index - 1) % separators.length]}#{token}"
    end.join
  end

  def set_first_response_versions(pack, versions)
    item = pack.fetch("items").first
    item["best_answer"] = versions.fetch("medium")
    item["response_versions"] = versions
    item.fetch("id")
  end

  def synthetic_v15_pack
    pack = deep_copy(load_pack("general"))
    pack["contract_version"] = "1.5.0"
    pack.fetch("items").each do |item|
      item["version"] = "1.5.0"
      item.delete("response_versions")
    end
    pack
  end

  def assert_inherited_v15_fields(item, label)
    follow_up = item.fetch("follow_up")
    assert follow_up.fetch("answer_anchors").is_a?(Array), "#{label} follow_up.answer_anchors"
    assert follow_up.fetch("answer_anchors").length.between?(2, 5), "#{label} follow_up.answer_anchors length"

    delayed = item.fetch("recall").fetch("delayed_variant")
    assert delayed.fetch("answer_anchors").is_a?(Array), "#{label} delayed answer_anchors"
    assert delayed.fetch("answer_anchors").length.between?(2, 5), "#{label} delayed answer_anchors length"
    assert_equal %w[certainty_update preserve revise verify], delayed.fetch("reasoning_moves").keys.sort, label
    assert delayed.fetch("reasoning_moves").values.all? { |move| move.is_a?(String) && move.length >= 20 }, label

    checks = item.fetch("critical_thinking").fetch("defense_checks")
    assert_equal 1, checks.length, label
    assert_equal 2, checks.fetch(0).fetch("distractors").length, label
  end

  def assert_response_version_error(validator, path_suffix, message, item_id:, target: "career", item_index: "0")
    field = path_suffix.sub(/\A\./, "")
    error = validator.errors.find { |candidate| candidate.path.end_with?(path_suffix) && candidate.message.include?(message) }
    refute_nil error, "expected #{path_suffix} to include #{message.inspect}; got #{validator.errors.map(&:to_s)}"
    assert_includes error.message, "target=#{target}"
    assert_includes error.message, "item_index=#{item_index}"
    assert_includes error.message, "item_id=#{item_id}"
    assert_includes error.message, "field=#{field}"
    assert_includes error.message, "reason="
  end

  def assert_collection_member_error(validator, collection, index, target: "dsa")
    error = validator.errors.find { |candidate| candidate.path == "#{collection}[#{index}]" }
    refute_nil error, "expected #{collection}[#{index}] member error; got #{validator.errors.map(&:to_s)}"
    assert_includes error.message, "target=#{target}"
    assert_includes error.message, "collection=#{collection}"
    assert_includes error.message, "index=#{index}"
    assert_includes error.message, "reason=must be a Hash"
  end

  def assert_collection_shape_error(validator, collection, path:, target: "dsa")
    error = validator.errors.find { |candidate| candidate.path == path }
    refute_nil error, "expected #{path} collection shape error; got #{validator.errors.map(&:to_s)}"
    assert_includes error.message, "target=#{target}"
    assert_includes error.message, "collection=#{collection}"
    assert_includes error.message, "reason=must be an array"
  end

  def promoted_pack
    pack = deep_copy(load_pack("career"))
    pack["contract_version"] = "1.6.0"
    pack.fetch("items").each do |item|
      item["version"] = "1.6.0"
      item["best_answer"] = MEDIUM
      item["response_versions"] = response_versions(medium: MEDIUM)
      item.fetch("distractors").each_with_index do |distractor, index|
        distractor["text"] = index.zero? ? DISTRACTOR_A : DISTRACTOR_B
      end
    end
    pack
  end
end
