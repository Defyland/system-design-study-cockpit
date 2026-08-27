require "test_helper"
require "yaml"
require_relative "../../lib/english_arcade/pack_validator"

class EnglishArcadeContentQualityTest < ActiveSupport::TestCase
  PACKS = %w[databases general].freeze
  CANONICAL_INTERVIEW_PACKS = %w[dsa ruby rails react golang elixir system-design].freeze
  REQUIRED = %w[follow_up compression feynman black_box recall sources].freeze
  REJECTED_BOILERPLATE = [
    /if the traffic or correctness requirement changed/i,
    /what part of your .* answer would you revisit first/i,
    /compress the .* answer to decision, caveat, evidence/i,
    /a teammate deciding what to do next/i,
    /use one concrete failure mode or observation/i,
    /can they state the trade-off without naming a tool first/i,
    /the answer jumped to a familiar shortcut/i,
    /a decision with a limit and a check/i,
    /the rule was memorised without its trigger/i,
    /start with the risk, then add one measurable next step/i,
    /not add a second check for/i,
    /keep .* simple and deal with a different failure/i
  ].freeze

  COVERAGE_MATRIX = {
    "ruby" => { "object model" => %w[ruby-02-method-lookup], "blocks/Enumerable" => %w[ruby-01-blocks-vs-procs ruby-03-enumerable-choice], "prudent metaprogramming" => %w[ruby-07-metaprogramming-restraint], "performance" => %w[ruby-04-memory-allocation ruby-08-frozen-strings], "concurrency" => %w[ruby-05-gvl-concurrency], "errors/tests" => %w[ruby-06-error-contracts ruby-09-testing-boundaries] },
    "rails" => { "request lifecycle" => %w[rails-06-service-objects], "AR/N+1/transactions" => %w[rails-01-n-plus-one rails-02-transaction-boundaries], "jobs/idempotency" => %w[rails-03-idempotent-jobs], "caching" => %w[rails-05-caching-strategy], "security" => %w[rails-04-strong-parameters], "observability" => %w[rails-07-observability], "API/migrations" => %w[rails-11-api-versioning rails-08-migration-safety] },
    "react" => { "rendering/state" => %w[react-03-key-prop react-01-state-ownership], "effects/fetching" => %w[react-02-effect-misuse react-04-data-fetching], "accessibility" => %w[react-05-accessibility], "performance" => %w[react-06-memoisation react-09-list-virtualisation], "tests/architecture" => %w[react-10-code-review-tone] },
    "golang" => { "interfaces" => %w[golang-01-interface-placement golang-09-nil-interface], "goroutines/channels" => %w[golang-02-goroutine-leak golang-05-channel-vs-mutex], "context/errors" => %w[golang-03-context-propagation golang-04-error-wrapping], "concurrency/profiling" => %w[golang-08-graceful-shutdown golang-06-profiling], "service boundaries" => %w[golang-10-service-boundaries] },
    "elixir" => { "processes/OTP/supervision" => %w[elixir-01-process-model elixir-03-genserver-bottleneck elixir-04-supervision-strategy], "immutability" => %w[elixir-06-immutability-cost], "backpressure" => %w[elixir-05-back-pressure], "fault tolerance" => %w[elixir-02-let-it-crash], "tests" => %w[elixir-12-onboarding-others] },
    "databases" => { "model/index/plan" => %w[databases-01-modeling-constraints databases-02-indexes-workload databases-03-explain-query-plans], "isolation/locks" => %w[databases-04-isolation-retries databases-05-locks-deadlocks], "replication/partition" => %w[databases-06-replication-lag databases-07-partitioning-pruning], "migration/tradeoffs" => %w[databases-08-zero-downtime-migrations databases-12-datastore-tradeoffs] },
    "system_design" => { "requirements/security" => %w[system_design-01-requirements-first], "estimates/capacity" => %w[system_design-02-volume-estimation system_design-10-bottleneck-naming], "API/data" => %w[system_design-08-rails-mapping system_design-03-source-of-truth], "consistency/failures" => %w[system_design-09-consistency-choice system_design-06-failure-modes], "observability/tradeoffs" => %w[system_design-10-bottleneck-naming system_design-07-tradeoff-defence] },
    "dsa" => { "patterns/invariants" => %w[dsa-01-pattern-naming dsa-02-invariant-statement], "complexity/proof" => %w[dsa-03-complexity-defence dsa-02-invariant-statement], "edge cases/debug" => %w[dsa-10-edge-case-enumeration dsa-06-mid-problem-recovery], "live communication" => %w[dsa-09-whiteboard-thinking-aloud] },
    "general" => { "intro/small talk/clarification" => %w[general-01-introduction general-02-small-talk general-03-clarification], "disagreement/negotiation" => %w[general-04-respectful-disagreement general-05-scope-negotiation], "STAR/stakeholder/incident" => %w[general-06-star-conflict general-08-stakeholder-mediation general-09-incident-update], "unknowns/turn-taking/close" => %w[general-10-handling-unknowns general-11-turn-taking general-12-interview-close] }
  }.freeze

  COACHING_EVIDENCE = {
    "rails-06-service-objects" => [ /Rack/i, /router/i, /controller/i, /record invariant/i, /HTTP response/i ],
    "react-10-code-review-tone" => [ /component boundary/i, /behaviou?r/i, /test/i, /loading/i, /success/i, /failure/i ],
    "elixir-12-onboarding-others" => [ /ExUnit/i, /public function/i, /supervisor/i, /returned behaviour/i ],
    "system_design-01-requirements-first" => [ /authorization/i, /abuse/i, /rate limits/i ],
    "system_design-04-write-path" => [ /POST \/payments/i, /idempotency key/i, /201/i, /status and body/i, /different input/i ]
  }.freeze

  COACHING_SECTIONS = %w[feedback rephrase feynman black_box recall].freeze
  ELIXIR_ONBOARDING_BLACK_BOX_EVIDENCE = [ /ExUnit/i, /public function/i, /observable behaviour/i, /supervisor/i ].freeze
  PILOT_ITEMS = {
    "career" => "career-01-a-60-to-90-second-introduction",
    "general" => "general-01-introduction",
    "rails-experience" => "rails_experience-01-early-rails-integrations-and-geospatial-work",
    "dsa" => "dsa-01-pattern-naming"
  }.freeze
  PILOT_TEMPLATE_BANS = [
    /README/i,
    /story[- ]bank/i,
    /available material/i,
    /\bthe (?:document|record)\s+(?:says|shows|records)\b/i,
    /this answer anchor is a learner-facing hint/i,
    /this reasoning move is a learner-facing hint/i,
    /the follow[- ]up/i,
    /inspect .* evidence next/i,
    /workload for/i,
    /no longer fits the original resource bound/i,
    /your a 60\b/i,
    /the later .* review says/i,
    /what minimum input for/i
  ].freeze

  test "new canonical packs do not reuse visible content bundles and cite real local sources" do
    PACKS.each do |target|
      pack = YAML.safe_load_file(Rails.root.join("db/seeds/english_arcade/#{target}.yml"), aliases: false)
      items = pack.fetch("items")
      assert_equal items.length, items.map { |item| item.fetch("prompt") }.uniq.length
      assert_equal items.length, items.map { |item| item.fetch("context") }.uniq.length
      assert_equal items.length, items.map { |item| item.fetch("distractors").map { |d| d.fetch("text") } }.uniq.length
      assert_equal items.length, items.map { |item| item.fetch("feedback").sort }.uniq.length
      assert_equal items.length, items.map { |item| item.fetch("follow_up") }.uniq.length
      assert_equal items.length, items.map { |item| item.fetch("feynman").sort }.uniq.length
      assert_equal items.length, items.map { |item| item.fetch("black_box").sort }.uniq.length
      items.each do |item|
        assert_equal 2, item.fetch("distractors").length
        refute item.fetch("distractors").any? { |distractor| distractor.fetch("text").match?(/leave the interviewer|scenario, that would|in a production interview|could you explain|treat that as enough information|competing failure mode/i) }
        refute item.fetch("feedback").values.any? { |feedback| feedback.match?(/Open with the decision in this case|Put the caveat next to the condition|Name the boundary, observation|Give the interviewer a decision first/i) }
        refute item.fetch("feynman").values.any? { |cue| cue.match?(/the interviewer who asked:|Use the operational detail in this scenario|Could they repeat the decision/i) }
        refute item.fetch("black_box").values.any? { |cue| cue.match?(/Scenario anchor:/i) }
        assert_equal REQUIRED, (REQUIRED & item.keys)
        authored = [
          *item.fetch("distractors").map { |distractor| distractor.fetch("text") },
          *item.fetch("feedback").values,
          item.dig("follow_up", "prompt"), item.dig("compression", "prompt"),
          *item.fetch("feynman").values, *item.fetch("black_box").values
        ]
        REJECTED_BOILERPLATE.each do |pattern|
          refute authored.any? { |value| value.match?(pattern) }, "#{item.fetch("id")} contains #{pattern.inspect}"
        end
        item.fetch("sources").select { |source| source.fetch("repo") == "system-design-estudos" }.each do |source|
          assert File.file?(Rails.root.join("../system-design-estudos", source.fetch("path"))), source.fetch("path")
        end
      end
    end
  end

  test "production pack focus matrix covers every release competency" do
    COVERAGE_MATRIX.each do |target, competencies|
      pack = YAML.safe_load_file(Rails.root.join("db/seeds/english_arcade/#{target == "system_design" ? "system-design" : target}.yml"), aliases: false)
      item_ids = pack.fetch("items").index_by { |item| item.fetch("id") }
      competencies.each do |competency, ids|
        ids.each { |id| assert item_ids.key?(id), "#{target} must cover #{competency} with production item #{id}" }
      end
      COACHING_EVIDENCE.each do |id, patterns|
        next unless item_ids.key?(id)

        item = item_ids.fetch(id)
        assert_equal "1.4.0", item.fetch("version"), "#{id} must carry the critical-thinking revision"
        coaching = coaching_strings(item)
        patterns.each do |pattern|
          assert coaching.any? { |cue| cue.match?(pattern) }, "#{id} coaching must retain #{pattern.inspect}"
        end
      end
    end
  end

  test "Elixir onboarding Black Box coaches the public-boundary exercise" do
    pack = YAML.safe_load_file(Rails.root.join("db/seeds/english_arcade/elixir.yml"), aliases: false)
    item = pack.fetch("items").find { |entry| entry.fetch("id") == "elixir-12-onboarding-others" }

    assert item
    cues = item.fetch("black_box").values
    ELIXIR_ONBOARDING_BLACK_BOX_EVIDENCE.each do |pattern|
      assert cues.any? { |cue| cue.match?(pattern) }, "Elixir onboarding Black Box must retain #{pattern.inspect}"
    end
    refute cues.any? { |cue| cue.match?(/pipeline pairing exercise/i) }
  end

  test "all eighty-four canonical technical items have authored unique adaptive prompts" do
    items = CANONICAL_INTERVIEW_PACKS.flat_map do |filename|
      YAML.safe_load_file(Rails.root.join("db/seeds/english_arcade/#{filename}.yml"), aliases: false).fetch("items")
    end
    assert_equal 84, items.length
    follow_ups = items.map { |item| item.dig("follow_up", "prompt") }
    compressions = items.map { |item| item.dig("compression", "prompt") }
    assert_equal 84, follow_ups.length
    assert_equal 84, follow_ups.map { |prompt| EnglishArcade::PackValidator.normalize_prompt(prompt) }.uniq.length
    assert_equal 84, compressions.map { |prompt| EnglishArcade::PackValidator.normalize_prompt(prompt) }.uniq.length
    refute follow_ups.zip(compressions).any? { |follow_up, compression| EnglishArcade::PackValidator.normalize_prompt(follow_up) == EnglishArcade::PackValidator.normalize_prompt(compression) }
    assert follow_ups.all? { |prompt| prompt.is_a?(String) && prompt.strip.length >= 40 && prompt.include?("?") }
    assert compressions.all? { |prompt| prompt.is_a?(String) && prompt.strip.length >= 40 }
  end

  test "critical follow-up answers retain item evidence instead of challenge boilerplate" do
    items = %w[
      dsa ruby rails react golang elixir databases general career rails-experience
      go-experience elixir-experience system-design
    ].flat_map do |filename|
      YAML.safe_load_file(Rails.root.join("db/seeds/english_arcade/#{filename}.yml"), aliases: false).fetch("items")
    end

    normalized = items.map do |item|
      topic = EnglishArcade::PackValidator.normalize_prompt(item.fetch("topic"))
      EnglishArcade::PackValidator.normalize_prompt(item.dig("follow_up", "best_answer")).sub(topic, "topic")
    end
    assert_equal items.length, normalized.uniq.length
    items.each do |item|
      answer = item.dig("follow_up", "best_answer")
      refute_match(/\AI would (?:separate|compare|trace|update|make the hidden assumption) the .* recommendation/i, answer)
    end
  end

  test "all seven technical packs avoid rejected adaptive boilerplate" do
    items = CANONICAL_INTERVIEW_PACKS.flat_map do |filename|
      YAML.safe_load_file(Rails.root.join("db/seeds/english_arcade/#{filename}.yml"), aliases: false).fetch("items")
    end

    items.each do |item|
      [ item.dig("follow_up", "prompt"), item.dig("compression", "prompt") ].each do |prompt|
        REJECTED_BOILERPLATE.each do |pattern|
          refute prompt.match?(pattern), "#{item.fetch("id")} contains #{pattern.inspect}"
        end
      end
    end
  end

  test "critical thinking is authored across every canonical item and card" do
    files = %w[
      dsa ruby rails react golang elixir databases general career rails-experience
      go-experience elixir-experience system-design
    ]
    packs = files.map { |file| YAML.safe_load_file(Rails.root.join("db/seeds/english_arcade/#{file}.yml"), aliases: false) }
    items = packs.flat_map { |pack| pack.fetch("items") }
    cards = packs.flat_map { |pack| pack.fetch("cards") }
    pack_by_item = packs.flat_map { |pack| pack.fetch("items").map { |item| [ item.fetch("id"), pack ] } }.to_h

    assert_equal 164, items.length
    assert_equal 39, cards.length
    items.each do |item|
      pack = pack_by_item.fetch(item.fetch("id"))
      contract_version = pack.fetch("contract_version")
      expected_item_version = {
        "1.4.0" => "1.4.0",
        "1.5.0" => "1.5.0",
        "1.6.0" => "1.6.0"
      }.fetch(contract_version)
      assert_equal expected_item_version, item.fetch("version")
      critical = item.fetch("critical_thinking")
      expected_critical_keys = %w[certainty claim_map comparison evidence_check failure_probe problem_frame rubric]
      transition = contract_version == "1.5.0"
      requires_inherited_1_5_fields = transition || contract_version == "1.6.0"
      expected_critical_keys << "defense_checks" if requires_inherited_1_5_fields || critical.key?("defense_checks")
      assert_equal expected_critical_keys.sort, critical.keys.sort
      assert_equal %w[fact inference assumption unknown].sort, critical.fetch("claim_map").keys.sort
      assert_equal %w[facts_correct assumptions_explicit alternatives_considered tradeoff_quality follow_up_adaptation certainty_calibration].sort, critical.fetch("rubric").keys.sort
      assert_includes %w[counterexample edge_case failure_mode], critical.dig("failure_probe", "kind")
      assert_includes %w[high medium low], critical.dig("certainty", "level")
      assert_equal "2026-08-25", critical.dig("evidence_check", "checked_on")
      follow_up_keys = %w[best_answer challenge_kind distractors goal prompt]
      follow_up_keys << "answer_anchors" if requires_inherited_1_5_fields || item.fetch("follow_up").key?("answer_anchors")
      assert_equal follow_up_keys.sort, item.fetch("follow_up").keys.sort
      assert_equal 2, item.dig("follow_up", "distractors").length
      assert_equal %w[goal prompt].sort, item.fetch("compression").keys.sort
      assert_equal %w[goal prompt].sort, item.fetch("extension").keys.sort
      assert item.dig("feynman", "reasoning_check").present?
      assert item.dig("black_box", "reasoning_error").present?
      assert_equal %w[active_recall_cue black_box_probe delayed_variant feynman_prompt leitner_start_box mastery_threshold].sort, item.fetch("recall").keys.sort
      delayed = item.dig("recall", "delayed_variant")
      delayed_keys = %w[active_recall_cue black_box_probe delayed_variant feynman_prompt leitner_start_box mastery_threshold]
      expected_delayed_keys = %w[best_answer changed_constraint distractors id new_evidence prompt]
      expected_delayed_keys << "answer_anchors" if requires_inherited_1_5_fields || delayed.key?("answer_anchors")
      expected_delayed_keys << "reasoning_moves" if requires_inherited_1_5_fields || delayed.key?("reasoning_moves")
      assert_equal expected_delayed_keys.sort, delayed.keys.sort
      assert_equal 2, delayed.fetch("distractors").length

      if requires_inherited_1_5_fields || item.fetch("follow_up").key?("answer_anchors")
        anchors = item.fetch("follow_up").fetch("answer_anchors")
        assert anchors.length.between?(2, 5)
        assert anchors.all? { |anchor| anchor.is_a?(String) && anchor.length >= 12 }
      end
      if requires_inherited_1_5_fields || delayed.key?("answer_anchors")
        anchors = delayed.fetch("answer_anchors")
        assert anchors.length.between?(2, 5)
        assert anchors.all? { |anchor| anchor.is_a?(String) && anchor.length >= 12 }
      end
      if requires_inherited_1_5_fields || delayed.key?("reasoning_moves")
        assert_equal %w[certainty_update preserve revise verify], delayed.fetch("reasoning_moves").keys.sort
        assert delayed.fetch("reasoning_moves").values.all? { |move| move.is_a?(String) && move.length >= 20 }
      end
      if requires_inherited_1_5_fields || critical.key?("defense_checks")
        checks = critical.fetch("defense_checks")
        assert_equal 1, checks.length
        check = checks.fetch(0)
        assert_equal %w[axis best_answer distractors id prompt].sort, check.keys.sort
        assert check.fetch("id").start_with?("#{item.fetch("id")}-defense-")
        assert_includes %w[facts assumptions alternatives tradeoff adaptation certainty], check.fetch("axis")
        assert check.fetch("prompt").include?("?")
        assert_equal 2, check.fetch("distractors").length
      end
    end
    cards.each do |card|
      assert_equal %w[check cue].sort, card.fetch("critical_thinking").keys.sort
    end

    packs.each do |pack|
      assert_equal 5, pack.fetch("items").map { |item| item.dig("follow_up", "challenge_kind") }.uniq.length
      assert pack.fetch("items").group_by { |item| item.dig("follow_up", "challenge_kind") }.values.all? { |group| group.length >= 2 }
      assert_equal %w[counterexample edge_case failure_mode].sort, pack.fetch("items").map { |item| item.dig("critical_thinking", "failure_probe", "kind") }.uniq.sort
      assert pack.fetch("items").count { |item| item.dig("critical_thinking", "comparison", "applicable") == false }.positive?
    end
  end

  test "transitional pilot items author critical decisions and reject malformed optional fields" do
    pilot_items = PILOT_ITEMS.map do |filename, id|
      pack = YAML.safe_load_file(Rails.root.join("db/seeds/english_arcade/#{filename}.yml"), aliases: false)
      [ filename, pack, pack.fetch("items").find { |item| item.fetch("id") == id } ]
    end

    pilot_items.each do |filename, _pack, item|
      assert item, "missing pilot item #{filename}"
      follow_up = item.fetch("follow_up")
      assert follow_up.key?("answer_anchors"), "#{item.fetch("id")} must author follow-up answer anchors"
      assert follow_up.fetch("answer_anchors").length.between?(2, 5)
      assert follow_up.fetch("answer_anchors").all? { |anchor| anchor.is_a?(String) && anchor.length >= 12 }

      delayed = item.dig("recall", "delayed_variant")
      assert delayed.key?("answer_anchors"), "#{item.fetch("id")} must author delayed answer anchors"
      assert delayed.fetch("answer_anchors").length.between?(2, 5)
      assert delayed.fetch("answer_anchors").all? { |anchor| anchor.is_a?(String) && anchor.length >= 12 }
      assert delayed.key?("reasoning_moves"), "#{item.fetch("id")} must author delayed reasoning moves"
      assert_equal %w[certainty_update preserve revise verify], delayed.fetch("reasoning_moves").keys.sort
      assert delayed.fetch("reasoning_moves").values.all? { |move| move.is_a?(String) && move.length >= 20 }

      critical = item.fetch("critical_thinking")
      assert critical.key?("defense_checks"), "#{item.fetch("id")} must author defense checks"
      assert_equal 1, critical.fetch("defense_checks").length
      defense = critical.fetch("defense_checks").fetch(0)
      assert_equal %w[axis best_answer distractors id prompt].sort, defense.keys.sort
      assert defense.fetch("id").start_with?("#{item.fetch("id")}-defense-")
      assert_includes %w[facts assumptions alternatives tradeoff adaptation certainty], defense.fetch("axis")
      assert defense.fetch("prompt").include?("?")
      assert_equal 2, defense.fetch("distractors").length
      assert_equal true, critical.dig("comparison", "applicable"), item.fetch("id")
      assert_operator critical.dig("comparison", "alternatives").length, :>=, 2
      assert critical.dig("comparison", "alternatives").all? do |alternative|
        %w[option benefit cost_or_risk valid_when].all? { |key| alternative.fetch(key).is_a?(String) && alternative.fetch(key).length >= 20 }
      end
      assert critical.dig("comparison", "decision_rule").is_a?(String)

      learner_strings = pilot_learner_texts(item)
      PILOT_TEMPLATE_BANS.each do |pattern|
        refute learner_strings.any? { |value| value.match?(pattern) }, "#{item.fetch("id")} contains #{pattern.inspect}"
      end
    end

    career_pack = pilot_items.fetch(0).fetch(1)
    career_item = career_pack.fetch("items").find { |item| item.fetch("id") == PILOT_ITEMS.fetch("career") }
    malformed = YAML.safe_load(YAML.dump(career_pack), aliases: false)
    malformed.fetch("items").find { |item| item.fetch("id") == career_item.fetch("id") }.fetch("follow_up")["answer_anchors"] = [ "too short" ]
    errors = EnglishArcade::PackValidator.new(malformed, strict: true, reference_date: Date.new(2026, 8, 25)).tap(&:valid?).errors
    assert errors.any? { |error| error.path.end_with?("follow_up.answer_anchors[0]") }

    malformed = YAML.safe_load(YAML.dump(career_pack), aliases: false)
    malformed.fetch("items").find { |item| item.fetch("id") == career_item.fetch("id") }.fetch("critical_thinking").fetch("defense_checks").first["axis"] = "syntax"
    errors = EnglishArcade::PackValidator.new(malformed, strict: true, reference_date: Date.new(2026, 8, 25)).tap(&:valid?).errors
    assert errors.any? { |error| error.path.end_with?("defense_checks[0].axis") }

    malformed = YAML.safe_load(YAML.dump(career_pack), aliases: false)
    malformed.fetch("items").find { |item| item.fetch("id") == career_item.fetch("id") }.fetch("recall").fetch("delayed_variant").fetch("reasoning_moves").delete("verify")
    errors = EnglishArcade::PackValidator.new(malformed, strict: true, reference_date: Date.new(2026, 8, 25)).tap(&:valid?).errors
    assert errors.any? { |error| error.path.end_with?("delayed_variant.reasoning_moves") }

    injected_anchor_checked = YAML.safe_load(YAML.dump(career_pack), aliases: false)
    injected_anchor_item = injected_anchor_checked.fetch("items").find { |item| item.fetch("id") == career_item.fetch("id") }
    injected_anchor_item.fetch("follow_up").fetch("answer_anchors")[0] = "This answer anchor is a learner-facing hint rather than interview content."
    assert pilot_learner_texts(injected_anchor_item).any? { |value| value.match?(PILOT_TEMPLATE_BANS[4]) }, "injected answer-anchor metadiscourse must be rejected"

    injected_reasoning_checked = YAML.safe_load(YAML.dump(career_pack), aliases: false)
    injected_reasoning_item = injected_reasoning_checked.fetch("items").find { |item| item.fetch("id") == career_item.fetch("id") }
    injected_reasoning_item.fetch("recall").fetch("delayed_variant").fetch("reasoning_moves")["verify"] = "This reasoning move is a learner-facing hint rather than an actionable update."
    assert pilot_learner_texts(injected_reasoning_item).any? { |value| value.match?(PILOT_TEMPLATE_BANS[5]) }, "injected reasoning metadiscourse must be rejected"
  end

  test "current canonical packs contain exactly three 1.6 packs and no 1.5 packs" do
    files = %w[
      dsa ruby rails react golang elixir databases general career rails-experience
      go-experience elixir-experience system-design
    ]
    packs = files.map { |file| YAML.safe_load_file(Rails.root.join("db/seeds/english_arcade/#{file}.yml"), aliases: false) }
    versions = packs.group_by { |pack| pack.fetch("contract_version") }

    assert_equal 3, versions.fetch("1.6.0").length
    assert_equal %w[career general rails_experience], versions.fetch("1.6.0").map { |pack| pack.fetch("target").fetch("key") }.sort
    assert_equal 0, versions.fetch("1.5.0", []).length
    assert_equal 10, versions.fetch("1.4.0").length
  end

  test "synthetic General 1.5 items require authored reasoning fields and recursive learner-text scans" do
    packs = transition_packs
    assert_equal 1, packs.length
    assert_equal "general", packs.first.fetch("target").fetch("key")

    packs.each do |pack|
      assert_equal "1.5.0", pack.fetch("contract_version")
      pack.fetch("items").each do |item|
        follow_up = item.fetch("follow_up")
        assert_equal %w[answer_anchors best_answer challenge_kind distractors goal prompt].sort, follow_up.keys.sort
        assert follow_up.fetch("answer_anchors").length.between?(2, 5)
        assert follow_up.fetch("answer_anchors").all? { |anchor| anchor.is_a?(String) && anchor.length >= 12 }

        delayed = item.fetch("recall").fetch("delayed_variant")
        assert_equal %w[answer_anchors best_answer changed_constraint distractors id new_evidence prompt reasoning_moves].sort, delayed.keys.sort
        assert delayed.fetch("answer_anchors").length.between?(2, 5)
        assert delayed.fetch("answer_anchors").all? { |anchor| anchor.is_a?(String) && anchor.length >= 12 }
        assert_equal %w[certainty_update preserve revise verify], delayed.fetch("reasoning_moves").keys.sort
        assert delayed.fetch("reasoning_moves").values.all? { |move| move.is_a?(String) && move.length >= 20 }

        critical = item.fetch("critical_thinking")
        assert_equal %w[certainty claim_map comparison defense_checks evidence_check failure_probe problem_frame rubric].sort, critical.keys.sort
        checks = critical.fetch("defense_checks")
        assert_equal 1, checks.length
        check = checks.fetch(0)
        assert_equal %w[axis best_answer distractors id prompt].sort, check.keys.sort
        assert check.fetch("id").start_with?("#{item.fetch("id")}-defense-")
        assert_includes %w[facts assumptions alternatives tradeoff adaptation certainty], check.fetch("axis")
        assert_equal 2, check.fetch("distractors").length

        bans = PILOT_TEMPLATE_BANS
        if pack.dig("target", "key") == "career"
          bans += [ /\bPDF\b/i, /\bmaterial\b/i, /\b(?:the\s+)?document\b/i, /\b(?:the\s+)?record\b/i ]
        end
        bans.each do |pattern|
          refute transition_learner_texts(item).any? { |value| value.match?(pattern) }, "#{item.fetch("id")} contains #{pattern.inspect}"
        end
      end
    end
  end

  test "promoted field mutants remain rejected and injected anchor text is scanned" do
    pack = transition_packs.first
    item = pack.fetch("items").first

    missing = YAML.safe_load(YAML.dump(pack), aliases: false)
    missing_item = missing.fetch("items").find { |entry| entry.fetch("id") == item.fetch("id") }
    missing_item.fetch("follow_up").delete("answer_anchors")
    refute EnglishArcade::PackValidator.new(missing, strict: true).valid?

    injected = YAML.safe_load(YAML.dump(pack), aliases: false)
    injected_item = injected.fetch("items").find { |entry| entry.fetch("id") == item.fetch("id") }
    injected_item.fetch("follow_up").fetch("answer_anchors")[0] = "This answer anchor is a learner-facing hint rather than interview content."
    assert transition_learner_texts(injected_item).any? { |value| value.match?(PILOT_TEMPLATE_BANS[4]) }
  end

  private

  def text_values(value)
    case value
    when Hash
      value.values.flat_map { |child| text_values(child) }
    when Array
      value.flat_map { |child| text_values(child) }
    when String
      [ value ]
    else
      []
    end
  end

  def pilot_learner_texts(item)
    text_values([
      item.fetch("follow_up"),
      item.dig("recall", "delayed_variant"),
      item.fetch("critical_thinking")
    ])
  end

  def transition_packs
    pack = YAML.safe_load_file(Rails.root.join("db/seeds/english_arcade/general.yml"), aliases: false)
    pack["contract_version"] = "1.5.0"
    pack.fetch("items").each do |item|
      item["version"] = "1.5.0"
      item.delete("response_versions")
    end
    [ pack ]
  end

  def transition_learner_texts(item)
    text_values([
      item.fetch("follow_up"),
      item.dig("recall", "delayed_variant"),
      item.fetch("critical_thinking")
    ])
  end

  def coaching_strings(item)
    sections = COACHING_SECTIONS.flat_map { |section| item.fetch(section).values }
    %w[follow_up compression].each do |section|
      sections.concat(item.fetch(section).values) if item.key?(section)
    end
    sections
  end
end
