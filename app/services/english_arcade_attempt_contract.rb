# frozen_string_literal: true

require "digest"
require "json"
require "openssl"

# Server-owned contract for one visible Arcade variant. The YAML pack remains
# the authored source, but no controller grades against a freshly loaded pack
# after an attempt has been committed.
class EnglishArcadeAttemptContract
  CONTRACT_VERSION = "arcade-attempt-v1".freeze
  VARIANT_IDS = %w[initial follow_up delayed_variant rephrase compression extension].freeze
  CRITICAL_VARIANT_IDS = %w[initial follow_up delayed_variant].freeze
  ARTIFACT_FIELDS = %w[
    problem_frame
    evidence_verified evidence_inference evidence_assumption evidence_gap
    source_quality
    comparison_option_a comparison_option_b comparison_tradeoff comparison_switch_condition
    comparison_rejected_alternative comparison_hard_constraint comparison_decision_rule
    counterexample confidence_percent change_my_mind
  ].freeze
  SELF_RUBRIC_AXES = %w[clarity precision naturalness pragmatic_appropriateness technical_correctness].freeze
  PUBLIC_FEEDBACK_KEYS = %w[
    register hedging precision grammar pragmatics topic answer selected sources provenance
  ].freeze

  class InvalidChoice < StandardError; end

  def self.variants_for(item)
    item = stringify(item)
    initial = {
      "id" => "initial",
      "prompt" => item["prompt"],
      "context" => item["context"],
      "best_answer" => item["best_answer"],
      "distractors" => item["distractors"],
      "feedback" => item["feedback"],
      "check" => stringify(item["feynman"] || {}).merge(
        "feynman" => item.dig("feynman", "reasoning_check") || item.dig("feynman", "self_check"),
        "black_box" => item.dig("black_box", "reasoning_error") || item.dig("black_box", "repair")
      ),
      "critical_thinking" => item["critical_thinking"]
    }

    variants = { "initial" => initial }
    follow_up = item["follow_up"]
    if follow_up.is_a?(Hash)
      variants["follow_up"] = authored_variant(
        id: "follow_up", prompt: follow_up["prompt"], context: item["context"],
        best_answer: follow_up["best_answer"], distractors: follow_up["distractors"],
        goal: follow_up["goal"], check: follow_up_check(follow_up),
        critical: item["critical_thinking"], base_feedback: item["feedback"]
      )
    end

    delayed = item.dig("recall", "delayed_variant")
    if delayed.is_a?(Hash)
      variants["delayed_variant"] = authored_variant(
        id: "delayed_variant", prompt: delayed["prompt"], context: item["context"],
        best_answer: delayed["best_answer"], distractors: delayed["distractors"],
        goal: delayed["goal"], check: delayed_check(delayed),
        critical: item["critical_thinking"], base_feedback: item["feedback"]
      )
    end

    feynman_check = stringify(item["feynman"] || {})

    {
      "rephrase" => [ "rephrase", item.dig("rephrase", "prompt"), item["best_answer"], item["distractors"], item.dig("rephrase", "goal") ],
      "compression" => [ "compression", item.dig("compression", "prompt"), item["best_answer"], item["distractors"], item.dig("compression", "goal") ],
      "extension" => [ "extension", item.dig("extension", "prompt"), item["best_answer"], item["distractors"], item.dig("extension", "goal") ]
    }.each do |key, (id, prompt, best_answer, distractors, goal)|
      next unless prompt.present? && best_answer.present?

      variants[key] = authored_variant(
        id: id, prompt: prompt, context: item["context"], best_answer: best_answer,
        distractors: distractors, goal: goal, check: feynman_check, critical: item["critical_thinking"],
        base_feedback: item["feedback"]
      )
    end
    variants
  end

  def self.authored_variant(id:, prompt:, context:, best_answer:, distractors:, goal:, check:, critical:, base_feedback:)
    feedback = stringify(base_feedback || {}).merge(
      "variant_check" => stringify(check),
      "distractor_diagnoses" => Array(distractors).filter_map { |d| d.is_a?(Hash) ? d["why_wrong"] : nil }
    )
    feedback["variant_goal"] = goal.to_s if goal.to_s.present?
    {
      "id" => id, "prompt" => prompt, "context" => context, "best_answer" => best_answer,
      "distractors" => distractors, "feedback" => feedback, "check" => stringify(check),
      "critical_thinking" => variant_critical_thinking(id: id, critical: critical, check: check, goal: goal)
    }
  end
  private_class_method :authored_variant

  # Critical-thinking guidance is authored at the item level, but an adaptive
  # variant must not replay the initial question's pre-commit lens. The
  # artifact contract still needs the authored comparison branch so the server
  # can fail closed; retain only that boolean plus labels owned by the active
  # variant. The detailed frame, claims, failure probe, and certainty rationale
  # stay scoped to the initial variant.
  def self.variant_critical_thinking(id:, critical:, check:, goal:)
    return stringify(critical || {}) unless CRITICAL_VARIANT_IDS.include?(id.to_s)

    authored = stringify(critical || {})
    variant_check = stringify(check || {})
    {
      "variant_id" => id.to_s,
      "variant_scope" => id.to_s,
      "challenge_kind" => variant_check["challenge_kind"].to_s.presence,
      "variant_goal" => goal.to_s.presence,
      "comparison" => { "applicable" => authored.dig("comparison", "applicable") }
    }.compact
  end
  private_class_method :variant_critical_thinking

  # Follow-up Feynman guidance must be derived from the follow-up object, not
  # from the item's initial feynman block. Answer anchors remain server-side
  # contract data; the view renders only the goal/challenge explanation.
  def self.follow_up_check(follow_up)
    follow_up = stringify(follow_up || {})
    {
      "challenge_kind" => follow_up["challenge_kind"],
      "goal" => follow_up["goal"],
      "answer_anchors" => Array(follow_up["answer_anchors"]).presence
    }.compact
  end
  private_class_method :follow_up_check

  # Delayed recall has no initial feynman dependency. Its own changed
  # constraint, new evidence, and (when present) reasoning moves are enough to
  # reconstruct the post-commit check without inventing a new explanation.
  def self.delayed_check(delayed)
    delayed = stringify(delayed || {})
    reasoning_moves = stringify(delayed["reasoning_moves"] || {})
    {
      "changed_constraint" => delayed["changed_constraint"],
      "new_evidence" => delayed["new_evidence"],
      "answer_anchors" => Array(delayed["answer_anchors"]).presence,
      "reasoning_moves" => reasoning_moves.presence
    }.compact
  end
  private_class_method :delayed_check

  def self.variant_digest(variant)
    Digest::SHA256.hexdigest(canonical_json(variant))
  end

  def self.content_version(item)
    item = stringify(item)
    item["version"].to_s.presence || "unknown"
  end

  def self.materialize(variant, session_id:, card_key:)
    variant = stringify(variant)
    options = [
      { "text" => variant["best_answer"].to_s, "correct" => true },
      *Array(variant["distractors"]).first(3).map { |entry| { "text" => entry.is_a?(Hash) ? entry["text"].to_s : entry.to_s, "correct" => false } }
    ]
    digest = variant_digest(variant)
    options = options.each_with_index.map do |option, index|
      option.merge("id" => option_token(session_id, card_key, variant.fetch("id"), digest, index))
    end
    rotated = options.rotate(rotation(session_id, card_key, variant.fetch("id"), options.length))
    {
      "id" => variant.fetch("id"), "digest" => digest, "options" => rotated,
      "correct_choice" => rotated.find { |option| option["correct"] }.fetch("id"),
      "prompt" => variant["prompt"].to_s, "context" => variant["context"].to_s,
      "best_answer" => variant["best_answer"].to_s, "feedback" => stringify(variant["feedback"] || {}),
      "check" => stringify(variant["check"] || {}), "critical_thinking" => stringify(variant["critical_thinking"] || {})
    }
  end

  def self.snapshot(materialized, content_version:)
    {
      "contract_version" => CONTRACT_VERSION,
      "content_version" => content_version.to_s,
      "variant_id" => materialized.fetch("id"),
      "variant_digest" => materialized.fetch("digest"),
      "prompt" => materialized.fetch("prompt"),
      "context" => materialized.fetch("context"),
      "options" => materialized.fetch("options").map { |option| { "id" => option.fetch("id"), "text" => option.fetch("text") } }
    }
  end

  # The persisted prompt snapshot is server-owned evidence used to rehydrate
  # and verify an attempt. HTTP callers receive this reduced public shape;
  # digest binding remains in the server-side assessment and opaque tokens.
  def self.public_snapshot(materialized, content_version:)
    snapshot(materialized, content_version: content_version).except("variant_digest")
  end

  # Learner-facing Feynman guidance is a deliberately small DTO. The full
  # check remains in the frozen server contract, while this projection has no
  # answer anchors, reasoning moves, digest, provenance, or future variant.
  def self.public_feynman_dto(materialized)
    materialized = stringify(materialized || {})
    variant_id = materialized["id"].to_s.presence || materialized["variant_id"].to_s.presence
    check = stringify(materialized["check"] || {})
    feedback = stringify(materialized["feedback"] || {})
    dto = { "variant_id" => variant_id }

    case variant_id
    when "initial"
      dto.merge!(check.slice("concept", "explain_to", "constraint", "self_check", "reasoning_check"))
    when "follow_up"
      dto["instruction"] = check["goal"].to_s.presence
    when "delayed_variant"
      dto.merge!(check.slice("changed_constraint", "new_evidence"))
    else
      dto["instruction"] = feedback["variant_goal"].to_s.presence
    end

    dto.compact
  end

  # Public feedback may retain the authored language feedback axes, but never
  # the internal variant_check hash. The safe Feynman DTO is the only check
  # representation allowed across the response boundary.
  def self.public_feedback(materialized, feedback: nil)
    materialized = stringify(materialized || {})
    source = stringify(feedback || materialized["feedback"] || {})
    source = source.slice(*PUBLIC_FEEDBACK_KEYS)
    source.merge("feynman" => public_feynman_dto(materialized))
  end

  def self.frozen_contract(materialized, content_version:)
    snapshot(materialized, content_version: content_version).merge(
      "correct_choice" => materialized.fetch("correct_choice"),
      "answer_text" => materialized.fetch("best_answer"),
      "feedback" => materialized.fetch("feedback"),
      "check" => materialized.fetch("check"),
      "critical_thinking" => materialized.fetch("critical_thinking")
    )
  end

  def self.grade(materialized, answer_choice:, typed_answer: nil)
    selected = answer_choice.to_s.strip
    option = materialized.fetch("options").find { |candidate| candidate.fetch("id") == selected }
    raise InvalidChoice, "answer choice is not valid for this session/card/variant" unless option

    correct = ActiveSupport::SecurityUtils.secure_compare(
      Digest::SHA256.hexdigest(selected), Digest::SHA256.hexdigest(materialized.fetch("correct_choice"))
    )
    {
      "correct" => correct,
      "selected_choice" => selected,
      "selected_option" => option.fetch("text"),
      "answer_text" => materialized.fetch("best_answer"),
      "feedback" => materialized.fetch("feedback"),
      "contract" => frozen_contract(materialized, content_version: materialized.fetch("content_version", "unknown"))
    }
  end

  def self.artifact_from(input, critical_thinking:)
    payload = input.respond_to?(:to_h) ? input.to_h : {}
    critical_thinking = stringify(critical_thinking || {})
    values = ARTIFACT_FIELDS.to_h do |field|
      value = payload[field] || payload[field.to_sym]
      [ field, value.to_s.truncate(4_000, omission: "…").strip ]
    end
    confidence = Integer(payload["confidence_percent"] || payload[:confidence_percent], exception: false)
    values["confidence_percent"] = confidence if confidence
    applicable = critical_thinking.dig("comparison", "applicable")
    errors = []
    %w[problem_frame evidence_verified evidence_inference evidence_assumption evidence_gap source_quality counterexample change_my_mind].each do |field|
      errors << field if values.fetch(field).length < 8
    end
    if applicable == true
      %w[comparison_option_a comparison_option_b comparison_tradeoff comparison_switch_condition].each { |field| errors << field if values.fetch(field).length < 8 }
      errors << "comparison_option_a_and_b" if normalize(values.fetch("comparison_option_a")) == normalize(values.fetch("comparison_option_b"))
    elsif applicable == false
      %w[comparison_rejected_alternative comparison_hard_constraint comparison_decision_rule].each { |field| errors << field if values.fetch(field).length < 8 }
    else
      errors << "comparison_branch"
    end
    errors << "confidence_percent" unless confidence && confidence.between?(0, 100)
    {
      "learner_classifications" => values.slice("evidence_verified", "evidence_inference", "evidence_assumption", "evidence_gap"),
      "problem_frame" => values.fetch("problem_frame"),
      "source_quality" => values.fetch("source_quality"),
      "comparison" => values.slice("comparison_option_a", "comparison_option_b", "comparison_tradeoff", "comparison_switch_condition", "comparison_rejected_alternative", "comparison_hard_constraint", "comparison_decision_rule").merge("authored_applicable" => applicable),
      "failure_probe" => stringify(critical_thinking["failure_probe"] || {}),
      "evidence_check" => stringify(critical_thinking["evidence_check"] || {}),
      "counterexample" => values.fetch("counterexample"),
      "confidence_percent" => confidence,
      "change_my_mind" => values.fetch("change_my_mind"),
      "captured_before_reveal" => true,
      "fact_contract_accuracy" => { "source" => "authored_reference", "assessment_scope" => "not_assessed", "value" => nil },
      "semantic_quality" => { "source" => "not_assessed", "assessment_scope" => "not_assessed", "value" => nil },
      "complete" => errors.empty?,
      "missing" => errors.uniq
    }
  end

  def self.mastery_eligible?(attempt)
    require_relative "english_arcade_evidence_eligibility"
    EnglishArcadeEvidenceEligibility.mastery?(attempt)
  end

  def self.normalize(value)
    value.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squeeze(" ").strip
  end

  def self.option_token(session_id, card_key, variant_id, digest, index)
    secret = if defined?(Rails) && Rails.application
      Rails.application.secret_key_base
    else
      "english-arcade-test-secret"
    end
    OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("SHA256"), secret, [ session_id, card_key, variant_id, digest, index ].join("\u0000"))[0, 48]
  end
  private_class_method :option_token

  def self.rotation(session_id, card_key, variant_id, size)
    return 0 if size.zero?

    Digest::SHA256.hexdigest([ session_id, card_key, variant_id ].join("\u0000")).to_i(16) % size
  end
  private_class_method :rotation

  def self.canonical_json(value)
    JSON.generate(sort_keys(stringify(value)))
  end
  private_class_method :canonical_json

  def self.sort_keys(value)
    case value
    when Hash
      value.keys.sort.each_with_object({}) { |key, result| result[key] = sort_keys(value.fetch(key)) }
    when Array
      value.map { |nested| sort_keys(nested) }
    else
      value
    end
  end
  private_class_method :sort_keys

  def self.stringify(value)
    case value
    when Hash then value.each_with_object({}) { |(key, nested), result| result[key.to_s] = stringify(nested) }
    when Array then value.map { |nested| stringify(nested) }
    else value
    end
  end
  private_class_method :stringify
end
