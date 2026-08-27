require "test_helper"
require "fileutils"
require "stringio"
require "tmpdir"
require "yaml"
require_relative "../../app/services/english_arcade_session_builder"
require_relative "../../lib/english_arcade/pack_loader"
require_relative "../../lib/english_arcade/pack_validator"
require_relative "../../lib/english_arcade/validate"

class EnglishArcadeAdaptiveDistractorContractTest < ActiveSupport::TestCase
  RATIO = EnglishArcade::Schema::BEST_ANSWER_TO_DISTRACTOR_WORD_RATIO
  WORD_CAP = EnglishArcade::Schema::MAX_DISTRACTOR_WORDS_FOR_LENGTH_TELL
  ADAPTIVE_DOMAINS = {
    "follow_up" => ->(item) { item.fetch("follow_up") },
    "delayed_variant" => ->(item) { item.fetch("recall").fetch("delayed_variant") },
    "defense_checks" => ->(item) { item.fetch("critical_thinking").fetch("defense_checks").fetch(0) }
  }.freeze

  test "v1.6 rejects follow-up, delayed, and defense length tell at their own paths" do
    ADAPTIVE_DOMAINS.each do |domain, fetcher|
      pack = balanced_v16_pack
      item = pack.fetch("items").first
      node = fetcher.call(item)
      set_ratio_case(node, best_words: 81, short_words: 49, long_words: 81)

      validator = EnglishArcade::PackValidator.new(pack, strict: true)

      refute_predicate validator, :valid?, domain
      length_errors = validator.errors.select { |candidate| candidate.message.include?("length alone reveals") }
      assert_equal [ expected_distractor_path(domain, 0) ], length_errors.map(&:path).uniq.sort, domain
      error = length_errors.first
      refute_nil error, "expected a length-tell error for #{domain}: #{validator.errors.map(&:to_s)}"
      assert_includes error.message, "49 words vs best answer 81"
      assert_includes error.message, "minimum 50 words"
      assert_includes error.message, "ratio 1.6"
      assert_includes error.message, "cap 50"
    end
  end

  test "v1.6 accepts the inclusive 1.6 boundary in all adaptive domains" do
    ADAPTIVE_DOMAINS.each do |domain, fetcher|
      pack = balanced_v16_pack
      node = fetcher.call(pack.fetch("items").first)
      set_ratio_case(node, best_words: 80, short_words: 50, long_words: 50)

      validator = EnglishArcade::PackValidator.new(pack, strict: true)

      assert_predicate validator, :valid?, "#{domain} at exactly 1.6 should be valid: #{validator.errors.map(&:to_s)}"
    end
  end

  test "1.6 obvious-short guard uses normalized word boundaries and the 50-word cap" do
    cases = [
      [ 80, 50, true ],
      [ 79, 49, false ],
      [ 110, 50, true ],
      [ 110, 49, false ]
    ]

    ADAPTIVE_DOMAINS.each do |domain, fetcher|
      cases.each do |best_words, distractor_words, expected_valid|
        pack = balanced_v16_pack
        node = fetcher.call(pack.fetch("items").first)
        set_ratio_case(node, best_words: best_words, short_words: distractor_words, long_words: best_words)

        validator = EnglishArcade::PackValidator.new(pack, strict: true)

        if expected_valid
          assert_predicate validator, :valid?, "#{domain} #{best_words}/#{distractor_words} should be valid: #{validator.errors.map(&:to_s)}"
        else
          refute_predicate validator, :valid?, "#{domain} #{best_words}/#{distractor_words} should be rejected"
          assert validator.errors.any? { |error| error.path == expected_distractor_path(domain, 0) && error.message.include?("length alone reveals") }, validator.errors.map(&:to_s)
        end
      end
    end
  end

  test "malformed adaptive distractors fail structurally without length-tell exceptions" do
    ADAPTIVE_DOMAINS.each do |domain, fetcher|
      malformed_adaptive_cases.each do |label, distractors, expected_error_suffix|
        pack = balanced_v16_pack
        node = fetcher.call(pack.fetch("items").first)
        set_ratio_case(node, best_words: 81, short_words: 49, long_words: 81)
        node["distractors"] = distractors
        validator = EnglishArcade::PackValidator.new(pack, strict: true)

        assert_nothing_raised { refute_predicate validator, :valid? }
        expected_path = "#{domain_path(domain)}#{expected_error_suffix}"
        assert validator.errors.any? { |error| error.path.end_with?(expected_path) }, "#{domain}: #{label}"
        refute validator.errors.any? { |error| error.message.include?("length alone reveals") }, "#{domain}: #{label}"
      end
    end
  end

  test "adaptive distractor hashes missing text fail structurally without length-tell" do
    ADAPTIVE_DOMAINS.each do |domain, fetcher|
      pack = balanced_v16_pack
      node = fetcher.call(pack.fetch("items").first)
      set_ratio_case(node, best_words: 81, short_words: 49, long_words: 81)
      node["distractors"] = [
        { "why_wrong" => "This alternative is plausible but misses the stated constraint." },
        { "text" => "E" * 50, "why_wrong" => "This alternative fails the evidence boundary." }
      ]
      validator = EnglishArcade::PackValidator.new(pack, strict: true)

      assert_nothing_raised { refute_predicate validator, :valid? }
      expected_path = "#{domain_path(domain)}[0].text"
      assert validator.errors.any? { |error| error.path.end_with?(expected_path) }, domain
      length_errors = validator.errors.select { |error| error.message.include?("length alone reveals") }
      assert_empty length_errors, domain
      assert_empty length_errors.select { |error| error.path.include?(domain_path(domain)) }, domain
      assert_empty length_errors.select { |error| (ADAPTIVE_DOMAINS.keys - [ domain ]).any? { |other| error.path.include?(domain_path(other)) } }, domain
    end
  end

  test "non-array adaptive distractors fail structurally without length-tell" do
    ADAPTIVE_DOMAINS.each do |domain, fetcher|
      pack = balanced_v16_pack
      node = fetcher.call(pack.fetch("items").first)
      set_ratio_case(node, best_words: 81, short_words: 49, long_words: 81)
      node["distractors"] = { "text" => "D" * 50, "why_wrong" => "This is not a distractor collection." }
      validator = EnglishArcade::PackValidator.new(pack, strict: true)

      assert_nothing_raised { refute_predicate validator, :valid? }
      assert validator.errors.any? { |error| error.path.end_with?(domain_path(domain)) }, domain
      length_errors = validator.errors.select { |error| error.message.include?("length alone reveals") }
      assert_empty length_errors, domain
      assert_empty length_errors.select { |error| error.path.include?(domain_path(domain)) }, domain
      assert_empty length_errors.select { |error| (ADAPTIVE_DOMAINS.keys - [ domain ]).any? { |other| error.path.include?(domain_path(other)) } }, domain
    end
  end

  test "distractor equal to the adaptive best answer keeps its dedicated error" do
    ADAPTIVE_DOMAINS.each do |domain, fetcher|
      pack = balanced_v16_pack
      node = fetcher.call(pack.fetch("items").first)
      node.fetch("distractors").first["text"] = node.fetch("best_answer")

      validator = EnglishArcade::PackValidator.new(pack, strict: true)

      refute_predicate validator, :valid?, domain
      assert validator.errors.any? { |error| error.path.include?(domain_path(domain)) && error.message.include?("duplicates the best answer") }, domain
    end
  end

  test "length enforcement is explicit to v1.6 and leaves 1.4, synthetic 1.5, and Salesforce semantics intact" do
    legacy = load_pack("dsa")
    assert_equal "1.4.0", legacy.fetch("contract_version")
    assert_predicate EnglishArcade::PackValidator.new(legacy, strict: true), :valid?

    transition = deep_copy(load_pack("general"))
    transition["contract_version"] = "1.5.0"
    transition.fetch("items").each do |item|
      item["version"] = "1.5.0"
      item.delete("response_versions")
    end
    assert_predicate EnglishArcade::PackValidator.new(transition, strict: true), :valid?

    salesforce = load_pack("salesforce")
    assert_equal "1.1.0", salesforce.fetch("contract_version")
    assert_predicate EnglishArcade::PackValidator.new(salesforce, strict: true), :valid?
  end

  test "synthetic v1.5 permits an explicit adaptive ratio violation on every surface" do
    ADAPTIVE_DOMAINS.each do |domain, fetcher|
      transition = transition_v15_pack
      set_ratio_case(fetcher.call(transition.fetch("items").first), best_words: 81, short_words: 49, long_words: 81)
      validator = EnglishArcade::PackValidator.new(transition, strict: true)

      assert_predicate validator, :valid?, "#{domain} should remain transitional debt: #{validator.errors.map(&:to_s)}"
      refute validator.errors.any? { |error| error.message.include?("length alone reveals") }, domain
    end
  end

  test "arbitrary metadata cannot enable v1.4 or disable v1.6 adaptive enforcement" do
    legacy = load_pack("dsa")
    legacy["metadata"] = { "adaptive_length_tell" => true }
    set_ratio_case(legacy.fetch("items").first.fetch("follow_up"), best_words: 81, short_words: 49, long_words: 81)

    assert_predicate EnglishArcade::PackValidator.new(legacy, strict: true), :valid?

    transition = transition_v15_pack
    transition["metadata"] = { "adaptive_length_tell" => true }
    set_ratio_case(transition.fetch("items").first.fetch("follow_up"), best_words: 81, short_words: 49, long_words: 81)

    assert_predicate EnglishArcade::PackValidator.new(transition, strict: true), :valid?

    promoted = balanced_v16_pack
    promoted["metadata"] = { "adaptive_length_tell" => false }
    set_ratio_case(promoted.fetch("items").first.fetch("follow_up"), best_words: 81, short_words: 49, long_words: 81)
    validator = EnglishArcade::PackValidator.new(promoted, strict: true)

    refute_predicate validator, :valid?
    assert_equal [ expected_distractor_path("follow_up", 0) ], validator.errors.select { |error| error.message.include?("length alone reveals") }.map(&:path).uniq.sort
  end

  test "invalid v1.6 packs are rejected by standalone loading and the runtime adapter" do
    Dir.mktmpdir("english-arcade-adaptive-contract") do |directory|
      source = Rails.root.join("db/seeds/english_arcade")
      Dir["#{source}/*.yml"].each { |path| FileUtils.cp(path, directory) }

      %w[career general].each do |target|
        File.write(File.join(directory, "#{target}.yml"), YAML.dump(balanced_v16_pack(target)))
      end

      invalid = balanced_v16_pack
      set_ratio_case(invalid.fetch("items").first.fetch("follow_up"), best_words: 81, short_words: 49, long_words: 81)
      File.write(File.join(directory, "career.yml"), YAML.dump(invalid))

      output = StringIO.new
      refute EnglishArcade::Validate.call(directory, io: output, strict: true)
      assert_includes output.string, "FAIL career"
      assert_includes output.string, "items[0].follow_up.distractors[0].text"

      error = assert_raises(ArgumentError) { EnglishArcade::PackLoader.new(directory).load("career", validate: true) }
      assert_includes error.message, "items[0].follow_up.distractors[0].text"
      assert_empty EnglishArcadeSessionBuilder::ContentPackAdapter.send(:validated_packs, { "career" => invalid })
    end
  end

  test "current Career and General v1.6 packs expose their remaining 36-set debt" do
    %w[career general].each do |target|
      pack = load_pack(target)
      assert_equal "1.6.0", pack.fetch("contract_version")
      sets = adaptive_sets(pack)
      assert_equal 36, sets.length
      assert_empty sets.flat_map { |set| set.fetch(:violations) }, target
    end
  end

  test "accepted content keeps response_versions out of the runtime card projection" do
    pack = balanced_v16_pack
    adapter = EnglishArcadeSessionBuilder::ContentPackAdapter.new({ "career" => pack }, source_name: "adaptive-contract-test")
    card = adapter.cards_for("career").first

    assert card
    refute_includes card.to_h.keys, :response_versions
    assert_equal pack.fetch("items").first.fetch("best_answer"), card.fetch(:answer_text)
  end

  private

  def load_pack(target)
    YAML.safe_load_file(Rails.root.join("db/seeds/english_arcade/#{target}.yml"), aliases: false)
  end

  def deep_copy(value)
    YAML.safe_load(YAML.dump(value), aliases: false)
  end

  def balanced_v16_pack(target = "career")
    pack = deep_copy(load_pack(target))
    pack["contract_version"] = "1.6.0"
    pack.fetch("items").each do |item|
      item["version"] = "1.6.0"
      balance_node(item.fetch("follow_up"))
      balance_node(item.fetch("recall").fetch("delayed_variant"))
      item.fetch("critical_thinking").fetch("defense_checks").each { |check| balance_node(check) }
    end
    pack
  end

  def transition_v15_pack
    pack = deep_copy(load_pack("general"))
    pack["contract_version"] = "1.5.0"
    pack.fetch("items").each do |item|
      item["version"] = "1.5.0"
      item.delete("response_versions")
    end
    pack
  end

  def balance_node(node)
    target_words = minimum_distractor_words(normalized_word_count(node.fetch("best_answer")))
    node.fetch("distractors").each_with_index do |distractor, index|
      suffix = " with evidence boundary #{index}"
      while normalized_word_count(distractor.fetch("text")) < target_words
        distractor["text"] << suffix
      end
    end
  end

  def set_ratio_case(node, best_words:, short_words:, long_words: nil)
    long_words ||= best_words
    node["best_answer"] = word_sentence(best_words, "adaptive_best")
    node.fetch("distractors").each_with_index do |distractor, index|
      word_count = index.zero? ? short_words : long_words
      prefix = index.zero? ? "short_distractor" : "long_distractor"
      distractor["text"] = word_sentence(word_count, prefix)
    end
  end

  def word_sentence(count, prefix)
    Array.new(count) { |index| "#{prefix}_#{index}" }.join(" ")
  end

  def normalized_word_count(value)
    value.to_s.gsub(/\p{Space}+/, " ").strip.split(" ").length
  end

  def minimum_distractor_words(best_words)
    [ (best_words.fdiv(RATIO)).ceil, WORD_CAP ].min
  end

  def domain_path(domain)
    case domain
    when "follow_up" then "follow_up.distractors"
    when "delayed_variant" then "recall.delayed_variant.distractors"
    when "defense_checks" then "critical_thinking.defense_checks[0].distractors"
    end
  end

  def expected_distractor_path(domain, index)
    "items[0].#{domain_path(domain)}[#{index}].text"
  end

  def malformed_adaptive_cases
    valid = ->(index) { { "text" => (index.zero? ? "D" : "E") * 50, "why_wrong" => "This plausible alternative fails a stated constraint #{index}." } }
    [
      [ "nil member", [ valid.call(0), nil ], "[1]" ],
      [
        "non-string text",
        [ { "text" => 42, "why_wrong" => "This explanation remains structurally present." }, valid.call(1) ],
        "[0].text"
      ],
      [ "missing why_wrong", [ { "text" => "F" * 50 }, valid.call(1) ], "[0].why_wrong" ],
      [ "non-string why_wrong", [ { "text" => "F" * 50, "why_wrong" => 42 }, valid.call(1) ], "[0].why_wrong" ]
    ]
  end

  def adaptive_sets(pack)
    pack.fetch("items").flat_map do |item|
      nodes = [
        [ "#{item.fetch('id')}.follow_up", item.fetch("follow_up") ],
        [ "#{item.fetch('id')}.delayed_variant", item.fetch("recall").fetch("delayed_variant") ]
      ]
      nodes.concat(item.fetch("critical_thinking").fetch("defense_checks").each_with_index.map { |check, index| [ "#{item.fetch('id')}.defense_checks[#{index}]", check ] })
      nodes.map do |label, node|
        best_words = normalized_word_count(node.fetch("best_answer"))
        minimum_words = minimum_distractor_words(best_words)
        violations = node.fetch("distractors").each_with_index.filter_map do |distractor, index|
          next unless distractor.is_a?(Hash) && distractor["text"].is_a?(String)
          next unless normalized_word_count(distractor["text"]) < minimum_words

          "#{label}.distractors[#{index}]"
        end
        { label: label, violations: violations }
      end
    end
  end
end
