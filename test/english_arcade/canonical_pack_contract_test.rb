require "test_helper"
require "stringio"
require "yaml"
require "fileutils"
require "tmpdir"
require_relative "../../lib/english_arcade/validate"

class EnglishArcadeCanonicalPackContractTest < ActiveSupport::TestCase
  test "strict production packs clear the twelve-item release bar" do
    output = StringIO.new

    valid = EnglishArcade::Validate.call(
      EnglishArcade::Validate::DEFAULT_DIRECTORY,
      io: output,
      strict: true
    )

    assert valid, output.string
    assert_includes output.string, "14/14 packs valid"
    assert_includes output.string, "canonical coverage: 13 required packs, 164 items; Salesforce is elective"
    assert_includes output.string, "content gate: >= 12 items per target"
  rescue Psych::SyntaxError => error
    flunk "canonical production pack is invalid YAML: #{error.message}"
  end

  test "strict validation rejects an answer leaked through a follow-up prompt" do
    pack = YAML.safe_load_file(Rails.root.join("db/seeds/english_arcade/databases.yml"), aliases: false)
    item = pack.fetch("items").first
    item.fetch("follow_up")["prompt"] = item.fetch("best_answer")
    validator = EnglishArcade::PackValidator.new(pack, strict: true)

    refute_predicate validator, :valid?
    assert validator.errors.any? { |error| error.path.end_with?(".follow_up") && error.message.include?("leaks the best answer") }
  end

  test "strict validation rejects an answer leaked through a compression prompt" do
    pack = YAML.safe_load_file(Rails.root.join("db/seeds/english_arcade/databases.yml"), aliases: false)
    item = pack.fetch("items").first
    item.fetch("compression")["prompt"] = item.fetch("best_answer")
    validator = EnglishArcade::PackValidator.new(pack, strict: true)

    refute_predicate validator, :valid?
    assert validator.errors.any? { |error| error.path.end_with?(".compression") && error.message.include?("leaks the best answer") }
  end

  test "strict validation rejects an answer leaked through a Feynman cue" do
    pack = YAML.safe_load_file(Rails.root.join("db/seeds/english_arcade/databases.yml"), aliases: false)
    item = pack.fetch("items").first
    item.fetch("feynman")["constraint"] = item.fetch("best_answer")
    validator = EnglishArcade::PackValidator.new(pack, strict: true)

    refute_predicate validator, :valid?
    assert validator.errors.any? { |error| error.path.end_with?(".feynman.constraint") && error.message.include?("leaks the best answer") }
  end

  test "provenance allows security implementation source but rejects secret material" do
    refute EnglishArcade::PackValidator.sensitive_evidence_path?("trustvault/internal/security/secrets.go")

    %w[
      trustvault/.env.production
      trustvault/config/credentials.yml.enc
      trustvault/config/master.key
      trustvault/.kamal/secrets
      trustvault/secrets/client.txt
      trustvault/private_key.pem
    ].each do |path|
      assert EnglishArcade::PackValidator.sensitive_evidence_path?(path), path
    end
  end

  test "canonical experience packs require authored adaptive prompts and malformed items fail closed" do
    pack = YAML.safe_load_file(Rails.root.join("db/seeds/english_arcade/go-experience.yml"), aliases: false)
    pack.fetch("items").first.fetch("follow_up").delete("prompt")
    validator = EnglishArcade::PackValidator.new(pack, strict: true)

    refute_predicate validator, :valid?
    assert validator.errors.any? { |error| error.path.end_with?(".follow_up.prompt") }
    assert_empty EnglishArcadeSessionBuilder::ContentPackAdapter.send(:validated_packs, { "go_experience" => pack })
  end

  test "canonical validator rejects a raw adaptive field and non-actionable compression framing" do
    pack = YAML.safe_load_file(Rails.root.join("db/seeds/english_arcade/dsa.yml"), aliases: false)
    pack.fetch("items").first["follow_up"] = "What would you change and how would you verify it?"
    pack.fetch("items").second.fetch("compression")["prompt"] = "In this answer there is no requested production format and the learner should simply keep talking."
    validator = EnglishArcade::PackValidator.new(pack, strict: true)

    refute_predicate validator, :valid?
    assert validator.errors.any? { |error| error.path.end_with?(".follow_up") && error.message.include?("Hash") }
    assert validator.errors.any? { |error| error.path.end_with?(".compression.prompt") && error.message.include?("actionable") }
  end

  test "canonical validator rejects identical follow-up and compression prompts" do
    pack = YAML.safe_load_file(Rails.root.join("db/seeds/english_arcade/dsa.yml"), aliases: false)
    item = pack.fetch("items").first
    item.fetch("compression")["prompt"] = item.fetch("follow_up").fetch("prompt")
    validator = EnglishArcade::PackValidator.new(pack, strict: true)

    refute_predicate validator, :valid?
    assert validator.errors.any? { |error| error.path.end_with?(".compression.prompt") && error.message.include?("follow-up") }
  end

  test "standalone validation invokes the cross-pack duplicate oracle" do
    Dir.mktmpdir("english-arcade-validator") do |directory|
      source = Rails.root.join("db/seeds/english_arcade")
      Dir["#{source}/*.yml"].each { |path| FileUtils.cp(path, directory) }
      dsa_path = File.join(directory, "dsa.yml")
      ruby_path = File.join(directory, "ruby.yml")
      dsa = YAML.safe_load_file(dsa_path, aliases: false)
      ruby = YAML.safe_load_file(ruby_path, aliases: false)
      dsa.fetch("items").first.fetch("follow_up")["prompt"] = ruby.fetch("items").first.dig("follow_up", "prompt")
      File.write(dsa_path, YAML.dump(dsa))
      output = StringIO.new

      refute EnglishArcade::Validate.call(directory, io: output, strict: true)
      assert_includes output.string, "FAIL cross-pack interview prompts"
    end
  end

  test "cross-pack oracle rejects missing and malformed item collections without coercion" do
    source = Rails.root.join("db/seeds/english_arcade/dsa.yml")
    probes = {
      "missing" => [ ->(pack) { pack.delete("items") }, "reason=missing items array" ],
      "nil" => [ ->(pack) { pack["items"] = nil }, "reason=must be an array (nil)" ],
      "string" => [ ->(pack) { pack["items"] = "not-an-array" }, "reason=must be an array" ]
    }

    probes.each do |label, (mutate, reason)|
      pack = YAML.safe_load_file(source, aliases: false)
      mutate.call(pack)
      errors = nil
      assert_nothing_raised { errors = EnglishArcade::PackValidator.cross_pack_prompt_errors("dsa" => pack) }

      error = errors.find { |entry| entry.include?("collection=items") }
      refute_nil error, "#{label} should produce a collection diagnostic: #{errors.inspect}"
      assert_includes error, "target=dsa"
      assert_includes error, "collection=items"
      assert_includes error, reason
    end

    valid_pack = YAML.safe_load_file(source, aliases: false)
    assert_empty EnglishArcade::PackValidator.cross_pack_prompt_errors("dsa" => valid_pack)

    malformed_member = YAML.safe_load_file(source, aliases: false)
    malformed_member.fetch("items") << nil
    member_errors = nil
    assert_nothing_raised do
      member_errors = EnglishArcade::PackValidator.cross_pack_prompt_errors("dsa" => malformed_member)
    end
    assert_empty member_errors
    member_validator = EnglishArcade::PackValidator.new(malformed_member, strict: true)
    refute_predicate member_validator, :valid?
    assert member_validator.errors.any? { |error| error.path == "items[12]" && error.message.include?("reason=must be a Hash") }
  end

  test "standalone summary marks invalid canonical item collections" do
    Dir.mktmpdir("english-arcade-invalid-items") do |directory|
      source = Rails.root.join("db/seeds/english_arcade")
      Dir["#{source}/*.yml"].each { |path| FileUtils.cp(path, directory) }
      dsa_path = File.join(directory, "dsa.yml")
      dsa = YAML.safe_load_file(dsa_path, aliases: false)
      dsa["items"] = nil
      File.write(dsa_path, YAML.dump(dsa))
      output = StringIO.new

      refute EnglishArcade::Validate.call(directory, io: output, strict: true)
      assert_includes output.string, "FAIL dsa"
      assert_includes output.string, "pack.items: target=dsa; collection=items; reason=must be an array (missing items array)"
      refute_includes output.string, "FAIL cross-pack interview prompts"
      assert_includes output.string, "canonical coverage: INVALID (dsa); 12/13 required packs valid, 152 items; Salesforce is elective"
      refute_includes output.string, "canonical coverage: 13 required packs, 0 items"
    end
  end

  test "critical-thinking mutants fail closed" do
    pack = YAML.safe_load_file(Rails.root.join("db/seeds/english_arcade/dsa.yml"), aliases: false)
    item = pack.fetch("items").first
    reference_date = Date.current
    future_date = reference_date + 1

    missing = Marshal.load(Marshal.dump(pack))
    missing.fetch("items").first.fetch("critical_thinking").delete("rubric")
    refute EnglishArcade::PackValidator.new(missing, strict: true).valid?

    bad_source = Marshal.load(Marshal.dump(pack))
    bad_source.fetch("items").first.fetch("critical_thinking").fetch("evidence_check")["source_kind"] = "invented_source"
    bad_source.fetch("items").first.fetch("critical_thinking").fetch("evidence_check")["checked_on"] = future_date.iso8601
    bad_validator = EnglishArcade::PackValidator.new(bad_source, strict: true, reference_date: reference_date)
    refute_predicate bad_validator, :valid?
    assert bad_validator.errors.any? { |error| error.path.end_with?("evidence_check.source_kind") }
    assert bad_validator.errors.any? { |error| error.path.end_with?("evidence_check.checked_on") }

    resume_derived = Marshal.load(Marshal.dump(pack))
    resume_derived.fetch("items").first.fetch("critical_thinking").fetch("evidence_check")["source_kind"] = "resume_derived"
    assert_predicate EnglishArcade::PackValidator.new(resume_derived, strict: true), :valid?

    future_reference = Marshal.load(Marshal.dump(pack))
    future_reference.fetch("items").first.fetch("critical_thinking").fetch("evidence_check")["checked_on"] = future_date.iso8601
    assert_predicate EnglishArcade::PackValidator.new(future_reference, strict: true, reference_date: future_date), :valid?
    future_validator = EnglishArcade::PackValidator.new(future_reference, strict: true, reference_date: reference_date)
    refute_predicate future_validator, :valid?
    assert future_validator.errors.any? { |error| error.path.end_with?("evidence_check.checked_on") }

    today_reference = Marshal.load(Marshal.dump(pack))
    today_reference.fetch("items").first.fetch("critical_thinking").fetch("evidence_check")["checked_on"] = reference_date.iso8601
    assert_predicate EnglishArcade::PackValidator.new(today_reference, strict: true, reference_date: reference_date), :valid?

    past_reference = Marshal.load(Marshal.dump(pack))
    past_reference.fetch("items").first.fetch("critical_thinking").fetch("evidence_check")["checked_on"] = (reference_date - 1).iso8601
    assert_predicate EnglishArcade::PackValidator.new(past_reference, strict: true, reference_date: reference_date), :valid?

    duplicated_alternatives = Marshal.load(Marshal.dump(pack))
    comparison = duplicated_alternatives.fetch("items").find { |entry| entry.dig("critical_thinking", "comparison", "applicable") }
    comparison.fetch("critical_thinking").fetch("comparison").fetch("alternatives")[1]["option"] = comparison.fetch("critical_thinking").fetch("comparison").fetch("alternatives")[0]["option"]
    duplicate_validator = EnglishArcade::PackValidator.new(duplicated_alternatives, strict: true)
    refute_predicate duplicate_validator, :valid?
    assert duplicate_validator.errors.any? { |error| error.message.include?("options must be distinct") }

    false_branch = Marshal.load(Marshal.dump(pack))
    false_item = false_branch.fetch("items").find { |entry| entry.dig("critical_thinking", "comparison", "applicable") == false }
    false_item.fetch("critical_thinking").fetch("comparison").delete("hard_constraint")
    refute EnglishArcade::PackValidator.new(false_branch, strict: true).valid?

    delayed_leak = Marshal.load(Marshal.dump(pack))
    delayed_item = delayed_leak.fetch("items").first
    delayed_item.fetch("recall").fetch("delayed_variant")["prompt"] = delayed_item.fetch("best_answer")
    delayed_validator = EnglishArcade::PackValidator.new(delayed_leak, strict: true)
    refute_predicate delayed_validator, :valid?
    assert delayed_validator.errors.any? { |error| error.path.end_with?("recall.delayed_variant.prompt") }

    delayed_duplicate = Marshal.load(Marshal.dump(pack))
    delayed_duplicate.fetch("items").first.fetch("recall").fetch("delayed_variant")["prompt"] = item.fetch("prompt")
    duplicate_delayed_validator = EnglishArcade::PackValidator.new(delayed_duplicate, strict: true)
    refute_predicate duplicate_delayed_validator, :valid?
    assert duplicate_delayed_validator.errors.any? { |error| error.path.end_with?("adaptive") }

    missing_text = Marshal.load(Marshal.dump(pack))
    missing_text.fetch("items").first.fetch("critical_thinking").fetch("claim_map")["fact"] = nil
    missing_text_validator = EnglishArcade::PackValidator.new(missing_text, strict: true)
    refute_predicate missing_text_validator, :valid?
    assert missing_text_validator.errors.any? { |error| error.path.end_with?("claim_map.fact") && error.message.include?("non-empty String") }

    repeated_determiner = Marshal.load(Marshal.dump(pack))
    repeated_determiner.fetch("items").first.fetch("critical_thinking").fetch("certainty")["rationale"] = "The a malformed learner-facing explanation should fail validation."
    repeated_validator = EnglishArcade::PackValidator.new(repeated_determiner, strict: true)
    refute_predicate repeated_validator, :valid?
    assert repeated_validator.errors.any? { |error| error.message.include?("repeated determiners") }
  end

  test "1.5 transition contract validates new reasoning fields without promoting packs" do
    legacy = YAML.safe_load_file(Rails.root.join("db/seeds/english_arcade/dsa.yml"), aliases: false)
    assert_equal "1.4.0", legacy.fetch("contract_version")
    assert_predicate EnglishArcade::PackValidator.new(legacy, strict: true), :valid?

    transition = transition_pack
    assert_equal "1.5.0", transition.fetch("contract_version")
    assert_predicate EnglishArcade::PackValidator.new(transition, strict: true), :valid?

    missing = Marshal.load(Marshal.dump(transition))
    missing.fetch("items").first.fetch("follow_up").delete("answer_anchors")
    missing.fetch("items").first.fetch("recall").fetch("delayed_variant").delete("reasoning_moves")
    missing.fetch("items").first.fetch("critical_thinking").delete("defense_checks")
    missing_validator = EnglishArcade::PackValidator.new(missing, strict: true)
    refute_predicate missing_validator, :valid?
    assert missing_validator.errors.any? { |error| error.path.end_with?(".follow_up") && error.message.include?("answer_anchors") }
    assert missing_validator.errors.any? { |error| error.path.end_with?(".delayed_variant") && error.message.include?("reasoning_moves") }
    assert missing_validator.errors.any? { |error| error.path.end_with?(".critical_thinking") && error.message.include?("defense_checks") }
  end

  test "1.5 transition fields reject malformed values and duplicate defense ids" do
    malformed = transition_pack
    item = malformed.fetch("items").first
    item.fetch("follow_up")["answer_anchors"] = [ "one anchor only" ]
    item.fetch("recall").fetch("delayed_variant").fetch("reasoning_moves")["unexpected"] = "This key is not part of the transition contract."
    item.fetch("critical_thinking").fetch("defense_checks").first["axis"] = "not_an_axis"
    item.fetch("critical_thinking").fetch("defense_checks").first["id"] = "not-item-bound"
    item.fetch("critical_thinking").fetch("defense_checks").first["prompt"] = item.fetch("best_answer")
    item.fetch("critical_thinking").fetch("defense_checks").first.fetch("distractors").first["text"] = item.fetch("critical_thinking").fetch("defense_checks").first.fetch("best_answer")
    item.fetch("recall").fetch("delayed_variant")["answer_anchors"] = [ nil, "A second concrete anchor for the delayed decision" ]
    malformed.fetch("items").second.fetch("critical_thinking").fetch("defense_checks").first["id"] = item.fetch("critical_thinking").fetch("defense_checks").first.fetch("id")

    validator = EnglishArcade::PackValidator.new(malformed, strict: true)
    refute_predicate validator, :valid?
    assert validator.errors.any? { |error| error.path.include?("answer_anchors") }
    assert validator.errors.any? { |error| error.path.include?("reasoning_moves") && error.message.include?("unknown keys") }
    assert validator.errors.any? { |error| error.path.end_with?(".axis") }
    assert validator.errors.any? { |error| error.path.end_with?(".id") && error.message.include?("item-bound") }
    assert validator.errors.any? { |error| error.path.end_with?(".prompt") && error.message.include?("leaks the best answer") }
    assert validator.errors.any? { |error| error.path.include?("distractors") && error.message.include?("duplicates the best answer") }
    assert validator.errors.any? { |error| error.path.include?("defense_checks") && error.message.include?("duplicate defense check ids") }
  end

  test "cross-pack oracle also covers critical-thinking prompts" do
    Dir.mktmpdir("english-arcade-critical-oracle") do |directory|
      source = Rails.root.join("db/seeds/english_arcade")
      Dir["#{source}/*.yml"].each { |path| FileUtils.cp(path, directory) }
      dsa_path = File.join(directory, "dsa.yml")
      ruby_path = File.join(directory, "ruby.yml")
      dsa = YAML.safe_load_file(dsa_path, aliases: false)
      ruby = YAML.safe_load_file(ruby_path, aliases: false)
      dsa.fetch("items").first.fetch("critical_thinking").fetch("failure_probe")["prompt"] = ruby.fetch("items").first.dig("critical_thinking", "failure_probe", "prompt")
      File.write(dsa_path, YAML.dump(dsa))
      output = StringIO.new

      refute EnglishArcade::Validate.call(directory, io: output, strict: true)
      assert_includes output.string, "FAIL cross-pack interview prompts"
    end
  end

  private

  def transition_pack
    pack = YAML.safe_load_file(Rails.root.join("db/seeds/english_arcade/dsa.yml"), aliases: false)
    pack["contract_version"] = "1.5.0"
    pack.fetch("items").each do |item|
      item["version"] = "1.5.0"
      item.fetch("follow_up")["answer_anchors"] = [
        "Name the invariant that makes this choice safe",
        "Connect the choice to the observed constraint"
      ]
      delayed = item.fetch("recall").fetch("delayed_variant")
      delayed["answer_anchors"] = [
        "Recalculate the decision under the changed constraint",
        "State which evidence would change your confidence"
      ]
      delayed["reasoning_moves"] = {
        "preserve" => "Keep the claim that remains supported by the unchanged constraint.",
        "revise" => "Change the recommendation when the new constraint breaks its premise.",
        "verify" => "Check the assumption against an observation before defending the choice.",
        "certainty_update" => "Lower or raise confidence and explain exactly why the evidence moved it."
      }
      item.fetch("critical_thinking")["defense_checks"] = [
        {
          "id" => "#{item.fetch("id")}-defense-1",
          "axis" => "facts",
          "prompt" => "Which verified fact would you establish before defending this decision to the interviewer?",
          "best_answer" => "I would name the observed constraint and connect it to the decision before claiming that the approach is safe.",
          "distractors" => [
            { "text" => "I would choose the familiar approach because it is usually accepted.", "why_wrong" => "Familiarity does not establish the fact or validate the decision boundary." },
            { "text" => "I would state the conclusion first and collect evidence only if challenged.", "why_wrong" => "That reverses the evidence check and hides the premise behind confidence." }
          ]
        }
      ]
    end
    pack
  end
end
