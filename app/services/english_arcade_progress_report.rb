# frozen_string_literal: true

class EnglishArcadeProgressReport
  require_relative "english_arcade_mock_evidence"
  require_relative "english_arcade_evidence_eligibility"
  AXES = %w[clarity precision naturalness pragmatic_appropriateness technical_correctness].freeze
  FEEDBACK_AXES = %w[register hedging precision grammar pragmatics].freeze
  MIN_TYPED_PRODUCTION_LENGTH = 40
  def initialize(learner_key:, since: 30.days.ago)
    @learner_key = learner_key
    @since = since
  end

  def call
    attempts = EnglishArcadeAttempt.where(learner_key: @learner_key).where("answered_at >= ?", @since).order(:answered_at).to_a
    revealed = attempts.select(&:feedback_revealed?)
    canonical_revealed = revealed.select { |attempt| canonical_attempt?(attempt) }
    observed_production = revealed.select { |attempt| attempt.diagnostic_evidence.dig("production", "typed_length").to_i >= MIN_TYPED_PRODUCTION_LENGTH }
    production = observed_production.select { |attempt| canonical_attempt?(attempt) }
    practice_days = production.map { |attempt| attempt.answered_at.to_date }.uniq.length
    direct = production.count { |attempt| attempt.diagnostic_evidence.dig("production", "english_directness") == "english_direct" }
    axis_report = AXES.to_h do |axis|
      values = production.filter_map { |attempt| attempt.diagnostic_evidence.dig("production", "self_rubric", axis) }
      [ axis, { "self_assessed" => true, "source" => "learner_self_report", "assessment_scope" => "report_only", "gate_eligible" => false, "count" => values.length, "average" => values.any? ? (values.sum.to_f / values.length).round(2) : nil } ]
    end
    delayed = delayed_metrics(revealed)
    adaptation = adaptation_metrics(attempts)
    critical = critical_metrics(revealed, adaptation, delayed)
    target_accuracy = accuracy_by_target(canonical_revealed)
    # Baseline pairing is an explicitly diagnostic check: retain an observed
    # baseline card even when its target is wrong so the report exposes the
    # mismatch instead of silently turning it into a missing card.
    baseline_attempts = observed_production.select { |attempt| EnglishArcadeCurriculum::BASELINE_ITEM_IDS.include?(attempt.card_key) }
      .group_by(&:card_key).transform_values { |item_attempts| item_attempts.min_by(&:answered_at) }.values
    baseline_item_ids = baseline_attempts.map(&:card_key)
    baseline_targets = baseline_attempts.map(&:target).uniq
    baseline_accuracy = accuracy_by_target(baseline_attempts)
    program_day = baseline_attempts.any? ? [ (Time.current.to_date - baseline_attempts.map(&:answered_at).min.to_date).to_i + 1, 1 ].max : 0
    mock_evidence = completed_mock_evidence(revealed)
    covered_item_ids = production.map(&:card_key).uniq
    canonical_item_accuracy = accuracy_by_item(canonical_revealed)
    practice_dates_by_item = production.group_by(&:card_key).transform_values { |items| items.map { |attempt| attempt.answered_at.to_date }.uniq }
    due_review_item_ids = due_review_item_ids(revealed)
    metrics = {
      "meaningful_typed" => production.length, "direct_english_eligible" => production.length,
      "direct_english_direct" => direct, "direct_english_rate" => rate(direct, production.length),
      "canonical_coverage" => (baseline_targets & EnglishArcadeCurriculum::CANONICAL_TARGETS).length,
      "completed_mock_targets" => mock_evidence.fetch("targets"),
      "completed_mock_ids" => mock_evidence.fetch("completed_ids"),
      "mock_counts" => mock_evidence.fetch("counts"),
      "covered_item_ids" => covered_item_ids,
      "canonical_item_accuracy" => canonical_item_accuracy,
      "practice_dates_by_item" => practice_dates_by_item,
      "due_review_item_ids" => due_review_item_ids,
      "due_reviews" => due_review_item_ids.length,
      # Gate counters use only server-owned contract evidence. The broader
      # report counters below remain visible as observed lineage, with their
      # assessment scope explicitly labelled.
      "follow_up_completed" => adaptation.fetch("server_follow_up_completed"), "technical_accuracy" => technical_accuracy(target_accuracy),
      "critical_pairs" => critical.fetch("critical_pairs"),
      "critical_targets" => critical.fetch("critical_targets"),
      "critical_pair_item_ids" => critical.fetch("critical_pair_item_ids"),
      "critical_pair_target_counts" => critical.fetch("critical_pair_target_counts"),
      "critical_pair_target_by_item" => critical.fetch("critical_pair_target_by_item"),
      "practice_days" => practice_days
    }.merge(
      "delayed_retest_eligible" => delayed.fetch("gate_eligible_cards"),
      "delayed_retest_successful" => delayed.fetch("gate_successful_cards"),
      "delayed_retest_high_quality" => delayed.fetch("gate_high_quality_cards"),
      "delayed_retest_rate" => delayed.fetch("gate_event_rate"),
      "delayed_retest_item_variant_ids" => delayed.fetch("gate_eligible_item_variant_ids"),
      "delayed_retest_successful_item_variant_ids" => delayed.fetch("gate_successful_item_variant_ids")
    ).merge(
      "fact_contract_accuracy" => critical.fetch("fact_contract_accuracy"),
      "problem_frame_presence" => critical.fetch("problem_frame_presence"),
      "explicit_assumptions_presence" => critical.fetch("explicit_assumptions_presence"),
      "source_quality_presence" => critical.fetch("source_quality_presence"),
      "alternatives_structurally_considered" => critical.fetch("alternatives_structurally_considered"),
      "tradeoff_observable_completeness" => critical.fetch("tradeoff_observable_completeness"),
      "semantic_quality" => critical.fetch("semantic_quality"),
      "correct_follow_up_adaptation" => critical.fetch("correct_follow_up_adaptation"),
      "certainty_brier" => critical.fetch("certainty_brier")
    )
    feedback_evidence = FEEDBACK_AXES.to_h { |axis| [ axis, { "observations" => revealed.count { |attempt| attempt.diagnostic_evidence.dig("feedback", axis).present? }, "attempts" => revealed.length } ] }
    response_times = attempts.filter_map(&:response_ms).select(&:positive?)
    {
      attempts: attempts.length, revealed: revealed.length, correct: revealed.count(&:correct?),
      targets: canonical_revealed.map(&:target).uniq.length, target_accuracy: target_accuracy,
      capture_evidence: { "typed_count" => attempts.count { |attempt| attempt.typed_answer.present? }, "meaningful_typed_count" => production.length },
      assignment_coverage: { "covered_item_ids" => covered_item_ids, "count" => covered_item_ids.length },
      direct_thinking: { "eligible" => production.length, "direct" => direct, "rate" => rate(direct, production.length), "source" => "learner_self_report", "assessment_scope" => "report_only", "gate_eligible" => false },
      self_rubric: axis_report, delayed_retention: delayed, follow_up_adaptation: adaptation,
      critical_thinking: critical,
      srs_reviews: { "due_completed" => metrics.fetch("due_reviews") },
      feedback_evidence: feedback_evidence,
      response_time_evidence: { "count" => response_times.length, "average_ms" => response_times.any? ? (response_times.sum.to_f / response_times.length).round : nil, "minimum_ms" => response_times.min, "maximum_ms" => response_times.max },
      skill_evidence: { "listening" => { "status" => "not_assessed", "evidence_count" => 0 }, "pronunciation" => { "status" => "not_assessed", "evidence_count" => 0 }, "spontaneous_fluency" => { "status" => "not_assessed", "evidence_count" => 0 } },
      baseline: baseline(baseline_attempts, baseline_item_ids, baseline_targets, baseline_accuracy), program_day: program_day, practice_days: practice_days, mocks: mock_evidence,
      black_box: attempts.count { |attempt| attempt.diagnostic_evidence["black_box_postmortem_present"] == true }, black_box_required: attempts.count { |attempt| attempt.diagnostic_evidence["black_box_required"] == true }, task_accuracy: task_accuracy(revealed),
      gates: EnglishArcadeCurriculum.plan.filter_map { |day| evaluate_gate(day, metrics, program_day) if day["gate"] },
      score_note: "Self-assessed typed practice evidence only. No CEFR certification or overall C2 result is assessed."
    }
  end

  private
  def delayed_metrics(revealed)
    observed = []; observed_successful = []; observed_high_quality = []
    gate_eligible = []; gate_successful = []; gate_high_quality = []
    revealed.each do |attempt|
      next unless attempt.feedback_revealed? && canonical_attempt?(attempt)
      next unless attempt.attempt_kind.to_s.in?(%w[retry follow_up]) || attempt.variant_key.to_s == "delayed_variant"

      prior = delayed_parent_for(attempt, strict: false)
      next unless delayed_spacing_valid?(prior, attempt)
      observed << attempt
      observed_successful << attempt if attempt.correct?
      observed_high_quality << attempt if attempt.quality_score.to_i >= 8

      next unless attempt.variant_key.to_s == "delayed_variant"
      next unless delayed_parent_item_ids.include?(attempt.card_key.to_s)
      gate_prior = delayed_parent_for(attempt, strict: true)
      next unless attempt.critical_eligible? && gate_prior&.critical_eligible?
      next unless delayed_spacing_valid?(gate_prior, attempt)
      next if same_variant_digest?(gate_prior, attempt)

      gate_eligible << attempt
      gate_successful << attempt if attempt.correct?
      gate_high_quality << attempt if attempt.quality_score.to_i >= 8
    end
    eligible_cards = observed.map(&:card_key).uniq
    successful_cards = observed_successful.map(&:card_key).uniq
    high_quality_cards = observed_high_quality.map(&:card_key).uniq
    gate_groups = gate_eligible.group_by(&:card_key)
    gate_eligible_cards = gate_groups.keys
    gate_successful_cards = gate_groups.filter_map { |card_key, items| card_key if items.any?(&:correct?) }
    gate_high_quality_cards = gate_groups.filter_map { |card_key, items| card_key if items.any? { |attempt| attempt.quality_score.to_i >= 8 } }
    gate_eligible_item_variant_ids = gate_eligible.map { |attempt| item_variant_id(attempt) }.compact.uniq
    gate_successful_item_variant_ids = gate_successful.filter_map { |attempt| item_variant_id(attempt) }.uniq
    gate_high_quality_item_variant_ids = gate_high_quality.filter_map { |attempt| item_variant_id(attempt) }.uniq
    {
      "eligible_events" => observed.length,
      "successful_events" => observed_successful.length,
      "high_quality_events" => observed_high_quality.length,
      "event_rate" => rate(observed_successful.length, observed.length),
      "eligible_cards" => eligible_cards.length,
      "successful_cards" => successful_cards.length,
      "high_quality_cards" => high_quality_cards.length,
      "assessment_scope" => "observed_lineage_report_only",
      "gate_eligible_events" => gate_eligible.length,
      "gate_successful_events" => gate_successful.length,
      "gate_high_quality_events" => gate_high_quality.length,
      # Gate rates are item-level, so repeated retries of one scheduled card
      # cannot inflate the denominator or the success numerator.
      "gate_event_rate" => rate(gate_successful_cards.length, gate_eligible_cards.length),
      "gate_eligible_cards" => gate_eligible_cards.length,
      "gate_successful_cards" => gate_successful_cards.length,
      "gate_high_quality_cards" => gate_high_quality_cards.length,
      "gate_eligible_item_ids" => gate_eligible_cards,
      "gate_successful_item_ids" => gate_successful_cards,
      "gate_eligible_item_variant_ids" => gate_eligible_item_variant_ids,
      "gate_successful_item_variant_ids" => gate_successful_item_variant_ids,
      "gate_high_quality_item_variant_ids" => gate_high_quality_item_variant_ids,
      "gate_assessment_scope" => "server_contract"
    }
  end
  def adaptation_metrics(attempts)
    observed_eligible = attempts.select { |attempt| reportable_attempt?(attempt) && canonical_attempt?(attempt) }.index_by(&:id)
    observed_completed = attempts.select do |attempt|
      reportable_attempt?(attempt) && adaptive_kind?(attempt) && attempt.correct? &&
        reportable_parent?(attempt, observed_eligible)
    end
    observed_parents = observed_completed.filter_map { |attempt| attempt.parent_attempt_id }.uniq
    observed_follow_up_parents = observed_completed.select { |attempt| attempt.attempt_kind.to_s == "follow_up" }.filter_map { |attempt| attempt.parent_attempt_id }.uniq
    observed_high = observed_completed.select { |attempt| attempt.quality_score.to_i >= 8 }.filter_map { |attempt| attempt.parent_attempt_id }.uniq

    server_eligible = attempts.select { |attempt| attempt.critical_eligible? && canonical_attempt?(attempt) }.index_by(&:id)
    server_completed = attempts.select do |attempt|
      attempt.critical_eligible? && adaptive_kind?(attempt) && attempt.correct? &&
        strict_parent?(attempt, server_eligible)
    end
    server_parent_items = server_completed.filter_map { |attempt| attempt.card_key if canonical_attempt?(attempt) }.uniq
    server_follow_up_items = server_completed.select { |attempt| attempt.attempt_kind.to_s == "follow_up" }.filter_map { |attempt| attempt.card_key if canonical_attempt?(attempt) }.uniq
    server_follow_up_attempts = server_completed.select { |attempt| attempt.attempt_kind.to_s == "follow_up" && canonical_attempt?(attempt) }
    server_follow_up_target_by_item = server_follow_up_attempts.each_with_object({}) do |attempt, targets|
      targets[attempt.card_key.to_s] = attempt.target.to_s
    end
    server_follow_up_targets = server_follow_up_target_by_item.values.uniq
    server_follow_up_target_counts = server_follow_up_target_by_item.values.tally
    server_high_items = server_completed.select { |attempt| attempt.quality_score.to_i >= 8 }.filter_map { |attempt| attempt.card_key if canonical_attempt?(attempt) }.uniq
    server_eligible_items = server_eligible.values.select { |attempt| attempt.attempt_kind.to_s == "initial" }.filter_map { |attempt| attempt.card_key if canonical_attempt?(attempt) }.uniq
    {
      "eligible" => observed_eligible.length,
      "completed" => observed_parents.length,
      "adaptation_completed" => observed_parents.length,
      "follow_up_completed" => observed_follow_up_parents.length,
      "high_quality" => observed_high.length,
      "rate" => rate(observed_parents.length, observed_eligible.length),
      "follow_up_rate" => rate(observed_follow_up_parents.length, observed_eligible.length),
      "assessment_scope" => "observed_lineage_report_only",
      "server_eligible" => server_eligible_items.length,
      "server_eligible_attempts" => server_eligible.length,
      "server_completed" => server_parent_items.length,
      "server_follow_up_completed" => server_follow_up_items.length,
      "server_follow_up_item_ids" => server_follow_up_items,
      "server_pair_item_ids" => server_follow_up_items,
      "server_follow_up_targets" => server_follow_up_targets,
      "server_follow_up_target_counts" => server_follow_up_target_counts,
      "server_pair_target_counts" => server_follow_up_target_counts,
      "server_follow_up_target_by_item" => server_follow_up_target_by_item,
      "server_pair_target_by_item" => server_follow_up_target_by_item,
      "server_eligible_item_ids" => server_eligible_items,
      "server_high_quality" => server_high_items.length,
      "server_rate" => rate(server_parent_items.length, server_eligible_items.length),
      "server_follow_up_rate" => rate(server_follow_up_items.length, server_eligible_items.length),
      "server_assessment_scope" => "server_contract"
    }
  end

  def critical_metrics(revealed, adaptation, delayed)
    critical = revealed.select { |attempt| attempt.critical_eligible? && canonical_attempt?(attempt) }
    artifacts = critical.map(&:critical_artifact)
    complete = artifacts.select { |artifact| artifact["complete"] == true }
    assumptions = complete.count { |artifact| artifact.dig("learner_classifications", "evidence_assumption").to_s.strip.length >= 8 }
    problem_frames = complete.count { |artifact| artifact["problem_frame"].to_s.strip.length >= 8 }
    source_quality = complete.count { |artifact| artifact["source_quality"].to_s.strip.length >= 8 }
    alternatives = complete.count do |artifact|
      comparison = artifact["comparison"].to_h
      if comparison["authored_applicable"] == true
        comparison["comparison_option_a"].to_s.strip.present? && comparison["comparison_option_b"].to_s.strip.present? &&
          comparison["comparison_option_a"].to_s.downcase != comparison["comparison_option_b"].to_s.downcase
      else
        comparison["comparison_rejected_alternative"].to_s.strip.present? && comparison["comparison_hard_constraint"].to_s.strip.present? && comparison["comparison_decision_rule"].to_s.strip.present?
      end
    end
    tradeoffs = complete.count do |artifact|
      comparison = artifact["comparison"].to_h
      comparison["authored_applicable"] == true ?
        comparison["comparison_tradeoff"].to_s.strip.present? && comparison["comparison_switch_condition"].to_s.strip.present? :
        comparison["comparison_hard_constraint"].to_s.strip.present? && comparison["comparison_decision_rule"].to_s.strip.present?
    end
    brier_values = critical.filter_map do |attempt|
      confidence = attempt.critical_artifact["confidence_percent"]
      next unless confidence.is_a?(Numeric)

      probability = confidence.to_f / 100.0
      (probability - (attempt.correct? ? 1.0 : 0.0))**2
    end
    {
      "critical_pairs" => adaptation.fetch("server_follow_up_completed"),
      "critical_targets" => adaptation.fetch("server_follow_up_targets").length,
      "critical_pair_item_ids" => adaptation.fetch("server_pair_item_ids"),
      "critical_pair_target_counts" => adaptation.fetch("server_pair_target_counts"),
      "critical_pair_target_by_item" => adaptation.fetch("server_pair_target_by_item"),
      "fact_contract_accuracy" => { "source" => "authored_reference", "assessment_scope" => "authored_reference_scored", "value" => rate(critical.count(&:correct?), critical.length) },
      "problem_frame_presence" => { "source" => "learner_artifact_structure", "assessment_scope" => "observed_presence", "value" => rate(problem_frames, complete.length) },
      "explicit_assumptions_presence" => { "source" => "learner_artifact_structure", "assessment_scope" => "observed_presence", "value" => rate(assumptions, complete.length) },
      "source_quality_presence" => { "source" => "learner_artifact_structure", "assessment_scope" => "observed_presence", "value" => rate(source_quality, complete.length) },
      "alternatives_structurally_considered" => { "source" => "authored_comparison_branch", "assessment_scope" => "observed_structure", "value" => rate(alternatives, complete.length) },
      "tradeoff_observable_completeness" => { "source" => "authored_comparison_branch", "assessment_scope" => "observed_structure", "value" => rate(tradeoffs, complete.length) },
      "semantic_quality" => { "source" => "assessor", "assessment_scope" => "not_assessed", "value" => nil },
      "correct_follow_up_adaptation" => { "source" => "authored_contract", "assessment_scope" => "server_observable", "value" => rate(adaptation.fetch("server_follow_up_completed"), adaptation.fetch("server_eligible")) },
      "certainty_brier" => { "source" => "authored_reference", "assessment_scope" => "authored_choice_only", "value" => brier_values.any? ? (brier_values.sum / brier_values.length).round(4) : nil },
      "artifact_count" => complete.length,
      "delayed_variant_count" => delayed.fetch("gate_eligible_cards")
    }
  end

  def reportable_attempt?(attempt)
    attempt.feedback_revealed? && attempt.typed_answer.to_s.strip.length >= MIN_TYPED_PRODUCTION_LENGTH && !attempt.spoken_text.present?
  end

  def canonical_attempt?(attempt)
    canonical_item_ids.include?(attempt.card_key.to_s) &&
      EnglishArcadeCurriculum.target_for(attempt.card_key).to_s == attempt.target.to_s
  end

  def canonical_item_ids
    @canonical_item_ids ||= EnglishArcadeCurriculum.required_item_ids_through(30).map(&:to_s).uniq
  end

  def delayed_parent_item_ids
    @delayed_parent_item_ids ||= EnglishArcadeCurriculum.plan.flat_map do |day|
      Array(day["spaced_reattempts"]).filter_map { |entry| entry["item_id"].to_s.presence }
    end.uniq
  end

  def adaptive_kind?(attempt)
    attempt.attempt_kind.to_s.in?(%w[retry rephrase follow_up compression extension])
  end

  def reportable_parent?(attempt, eligible)
    parent = attempt.parent_attempt
    parent && eligible.key?(parent.id) && same_card_lineage?(attempt, parent)
  end

  def strict_parent?(attempt, eligible)
    parent = attempt.parent_attempt
    return false unless parent && eligible.key?(parent.id) && same_card_lineage?(attempt, parent)
    return false unless EnglishArcadeEvidenceEligibility.same_lineage?(attempt, parent)
    return false unless attempt.variant_key.to_s.in?(EnglishArcadeAttemptContract::CRITICAL_VARIANT_IDS)

    if attempt.variant_key.to_s == "delayed_variant" || attempt.attempt_kind.to_s == "retry"
      parent.variant_key.to_s == "initial" && parent.answered_at && attempt.answered_at && (attempt.answered_at - parent.answered_at) >= 7.days
    else
      true
    end
  end

  def same_card_lineage?(attempt, parent)
    parent.learner_key.to_s == attempt.learner_key.to_s &&
      parent.target.to_s == attempt.target.to_s &&
      parent.card_key.to_s == attempt.card_key.to_s &&
      parent.feedback_revealed? && parent.answered_at && attempt.answered_at && parent.answered_at <= attempt.answered_at
  end

  def delayed_parent_for(attempt, strict:)
    parent = attempt.parent_attempt
    parent ||= EnglishArcadeAttempt.find_by(id: attempt.diagnostic_evidence.to_h["parent_attempt_id"])
    if parent && same_card_lineage?(attempt, parent) && parent.attempt_kind.to_s == "initial" && (!strict || parent.critical_eligible?)
      return parent
    end

    candidates = EnglishArcadeAttempt.where(
      learner_key: attempt.learner_key,
      target: attempt.target,
      card_key: attempt.card_key,
      attempt_kind: "initial",
      feedback_revealed: true
    ).where("answered_at < ?", attempt.answered_at).order(answered_at: :desc).to_a
    candidates.find do |candidate|
      same_card_lineage?(attempt, candidate) && (!strict || candidate.critical_eligible?)
    end
  end

  def delayed_spacing_valid?(parent, attempt)
    parent && parent.variant_key.to_s.in?([ "initial", "" ]) && parent.answered_at && attempt.answered_at &&
      parent.answered_at <= attempt.answered_at - 7.days
  end

  def same_variant_digest?(first, second)
    first_digest = first.diagnostic_evidence.to_h.dig("assessment", "variant_digest").to_s
    second_digest = second.diagnostic_evidence.to_h.dig("assessment", "variant_digest").to_s
    first_digest.present? && second_digest.present? && first_digest == second_digest
  end

  def item_variant_id(attempt)
    item_id = attempt.card_key.to_s.presence
    variant_id = attempt.variant_key.to_s.presence
    item_id && variant_id ? "#{item_id}:#{variant_id}" : nil
  end

  def due_review_item_ids(revealed)
    revealed.group_by(&:card_key).filter_map do |card_key, card_attempts|
      card_key if card_attempts.any? do |attempt|
        card_attempts.any? do |candidate|
          candidate.answered_at < attempt.answered_at && candidate.next_due_on.present? && attempt.answered_at.to_date >= candidate.next_due_on
        end
      end
    end.uniq
  end

  def due_reviews(revealed)
    # A same-session follow-up is useful transfer evidence, but it is not an
    # SRS review. Count a card once when a later revealed attempt reaches the
    # persisted due date from an earlier revealed attempt for that card.
    due_review_item_ids(revealed).length
  end
  def accuracy_by_target(revealed)
    revealed.group_by(&:target).transform_values { |list| { "revealed" => list.length, "correct" => list.count(&:correct?), "accuracy" => rate(list.count(&:correct?), list.length) } }
  end
  def accuracy_by_item(revealed)
    revealed.group_by { |attempt| attempt.card_key.to_s }.transform_values do |items|
      { "target" => items.first.target.to_s, "revealed" => items.length, "correct" => items.count(&:correct?), "accuracy" => rate(items.count(&:correct?), items.length) }
    end
  end
  def technical_accuracy(accuracy)
    values = EnglishArcadeCurriculum::TECHNICAL_TARGETS.filter_map { |target| accuracy.dig(target, "accuracy") }
    values.any? ? (values.sum / values.length).round(3) : nil
  end
  def baseline(attempts, item_ids, targets, accuracy)
    missing_items = EnglishArcadeCurriculum::BASELINE_ITEM_IDS - item_ids
    missing = EnglishArcadeCurriculum::CANONICAL_TARGETS - targets
    unexpected_items = item_ids - EnglishArcadeCurriculum::BASELINE_ITEM_IDS
    exact_item_set = item_ids.sort == EnglishArcadeCurriculum::BASELINE_ITEM_IDS.sort
    exact_target_set = targets.sort == EnglishArcadeCurriculum::CANONICAL_TARGETS.sort
    expected_target_pairs = EnglishArcadeCurriculum::BASELINE_ITEM_IDS.to_h do |card_key|
      [ card_key, EnglishArcadeCurriculum.target_for(card_key) ]
    end
    observed_target_pairs = attempts.index_by(&:card_key).transform_values(&:target)
    pairing_gaps = expected_target_pairs.each_with_object([]) do |(card_key, expected_target), gaps|
      actual_target = observed_target_pairs[card_key]
      next if actual_target == expected_target

      gaps << { "card_key" => card_key, "expected_target" => expected_target, "actual_target" => actual_target }
    end
    exact_target_pairing = exact_item_set && pairing_gaps.empty?
    axes = AXES.to_h do |axis|
      values = attempts.filter_map { |attempt| attempt.diagnostic_evidence.dig("production", "self_rubric", axis) }
      [ axis, { "count" => values.length, "average" => values.any? ? (values.sum.to_f / values.length).round(2) : nil } ]
    end
    direct = attempts.count { |attempt| attempt.diagnostic_evidence.dig("production", "english_directness") == "english_direct" }
    {
      "status" => exact_item_set && exact_target_set && exact_target_pairing ? "practice_evidence_collected" : "pending",
      "covered_targets" => targets,
      "missing_targets" => missing,
      "missing_item_ids" => missing_items,
      "unexpected_item_ids" => unexpected_items,
      "exact_item_set" => exact_item_set,
      "exact_target_pairing" => exact_target_pairing,
      "pairing_gaps" => pairing_gaps,
      "target_pairing" => {
        "exact" => exact_target_pairing,
        "expected" => expected_target_pairs,
        "observed" => observed_target_pairs,
        "gaps" => pairing_gaps
      },
      "technical_knowledge" => accuracy.slice(*EnglishArcadeCurriculum::TECHNICAL_TARGETS),
      "language_axes" => axes,
      "directness" => { "count" => attempts.length, "direct" => direct, "rate" => rate(direct, attempts.length) },
      "general_c2_calibrated_performance" => {
        "status" => attempts.any? { |attempt| attempt.target == "general" } ? "limited_one_item_typed_sample_not_overall_c2" : "not_yet_observed",
        "evidence" => accuracy["general"]
      }
    }
  end
  def evaluate_gate(day, metrics, program_day)
    thresholds = day.dig("gate", "thresholds")
    reasons = thresholds.filter_map do |key, expected|
      actual = gate_metric_value(key, expected, thresholds, metrics)
      "#{key}: #{actual.inspect} does not meet #{expected.inspect}" unless meets?(key, actual, expected)
    end
    status = if program_day < day["day"]
      "pending"
    elsif reasons.empty?
      "pass"
    else
      "fail"
    end
    { "day" => day["day"], "status" => status, "reasons" => reasons, "recovery" => day.dig("gate", "recovery"), "program_day" => program_day }
  end

  def gate_metric_value(key, expected, thresholds, metrics)
    required_item_ids = Array(thresholds["required_item_ids"]).map(&:to_s).uniq
    covered_item_ids = Array(metrics["covered_item_ids"]).map(&:to_s).uniq
    pair_item_ids = Array(metrics["critical_pair_item_ids"]).map(&:to_s).uniq
    delayed_ids = Array(metrics["delayed_retest_item_variant_ids"]).map(&:to_s).uniq
    delayed_expected_ids = Array(thresholds["required_delayed_item_variant_ids"]).map(&:to_s).uniq

    case key
    when "required_mock_ids"
      Array(metrics["completed_mock_ids"])
    when "required_mock_counts"
      metrics.fetch("mock_counts", {})
    when "required_item_ids"
      covered_item_ids & Array(expected).map(&:to_s)
    when "meaningful_typed"
      (covered_item_ids & required_item_ids).length
    when "canonical_coverage"
      (covered_item_ids & required_item_ids).filter_map { |item_id| canonical_target_for(item_id) }.uniq.length
    when "critical_pairs", "follow_up_completed"
      (pair_item_ids & required_item_ids).length
    when "critical_targets"
      gate_pair_target_counts(pair_item_ids & required_item_ids, metrics).length
    when "critical_target_pair_counts"
      gate_pair_target_counts(pair_item_ids & required_item_ids, metrics)
    when "delayed_retest_eligible"
      (delayed_ids & delayed_expected_ids).length
    when "delayed_retest_rate"
      successful_ids = Array(metrics["delayed_retest_successful_item_variant_ids"]).map(&:to_s).uniq
      eligible_ids = delayed_ids & delayed_expected_ids
      rate((successful_ids & delayed_expected_ids).length, eligible_ids.length)
    when "required_delayed_item_variant_ids"
      delayed_ids & Array(expected).map(&:to_s)
    when "technical_accuracy"
      item_accuracy = metrics.fetch("canonical_item_accuracy", {})
      values = (covered_item_ids & required_item_ids).filter_map do |item_id|
        entry = item_accuracy[item_id] || item_accuracy[item_id.to_sym]
        accuracy = entry && entry["accuracy"]
        accuracy if accuracy && EnglishArcadeCurriculum::TECHNICAL_TARGETS.include?(canonical_target_for(item_id))
      end
      values.any? ? (values.sum / values.length).round(3) : nil
    when "practice_days"
      dates_by_item = metrics.fetch("practice_dates_by_item", {})
      (covered_item_ids & required_item_ids).flat_map { |item_id| Array(dates_by_item[item_id] || dates_by_item[item_id.to_sym]) }.uniq.length
    when "due_reviews"
      (Array(metrics["due_review_item_ids"]).map(&:to_s) & required_item_ids).length
    else
      metrics[key]
    end
  end

  def gate_pair_target_counts(pair_item_ids, metrics)
    target_by_item = metrics.fetch("critical_pair_target_by_item", {}).to_h.transform_keys(&:to_s)
    pair_item_ids.each_with_object(Hash.new(0)) do |item_id, counts|
      target = target_by_item[item_id].presence || canonical_target_for(item_id)
      counts[target] += 1 if EnglishArcadeCurriculum::CANONICAL_TARGETS.include?(target.to_s)
    end
  end

  def canonical_target_for(item_id)
    target = EnglishArcadeCurriculum.target_for(item_id)
    target if EnglishArcadeCurriculum::CANONICAL_TARGETS.include?(target.to_s)
  rescue KeyError
    nil
  end

  def meets?(key, actual, expected)
    return (Array(expected) - Array(actual)).empty? if %w[required_mock_ids required_item_ids].include?(key)
    return Array(actual).map(&:to_s).sort == Array(expected).map(&:to_s).sort if key == "required_delayed_item_variant_ids"
    return expected.all? { |target, count| actual.to_h.fetch(target, 0) >= count } if %w[required_mock_counts critical_target_pair_counts].include?(key)
    return actual.to_f >= expected.to_f if key.end_with?("rate") || key == "technical_accuracy"
    actual.to_i >= expected.to_i
  end
  def rate(numerator, denominator)
    denominator.zero? ? nil : (numerator.to_f / denominator).round(3)
  end

  def task_accuracy(revealed)
    revealed.group_by { |attempt| "#{attempt.target}:#{attempt.card_key}" }.transform_values do |items|
      { "target" => items.first.target, "attempts" => items.length, "revealed" => items.length, "correct" => items.count(&:correct?), "accuracy" => rate(items.count(&:correct?), items.length) }
    end
  end

  def completed_mock_evidence(revealed)
    sessions = EnglishArcadeSession.where(learner_key: @learner_key, mode: %w[timed_30 timed_45], status: "completed").order(:id).to_a
    qualifying = sessions.filter_map do |session|
      evidence = EnglishArcadeMockEvidence.for(session: session, now: Time.current)
      evidence["qualifying"] ? evidence : nil
    end
    completed_ids = qualifying.map { |entry| entry.fetch("id") }.uniq
    completion_ratio = rate(completed_ids.length, EnglishArcadeCurriculum::MOCK_SPECS.length)
    {
      "targets" => qualifying.map { |entry| entry.fetch("target") }.uniq,
      "counts" => qualifying.map { |entry| entry.fetch("target") }.tally,
      "completed_ids" => completed_ids,
      "sessions" => qualifying,
      "completed_ratio" => completion_ratio,
      "completion_ratio" => completion_ratio,
      "ratio" => rate(qualifying.length, sessions.length),
      "minimum_completion_ratio" => 0.9
    }
  end
end
