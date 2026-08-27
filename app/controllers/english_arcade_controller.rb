class EnglishArcadeController < ApplicationController
  require "ostruct"
  require_relative "../services/english_arcade_attempt_contract"
  require_relative "../services/english_arcade_evidence_eligibility"
  require_relative "../services/english_arcade_mock_evidence"
  ANSWER_STATUSES = %w[submitted correct wrong partial reveal skip error].freeze
  RESET_STATUSES = %w[wrong partial reveal skip].freeze
  FEEDBACK_AXES = %w[register hedging precision grammar pragmatics].freeze
  UNASSESSED_SKILLS = %w[listening pronunciation spontaneous_fluency].freeze
  SELF_RUBRIC_AXES = %w[clarity precision naturalness pragmatic_appropriateness technical_correctness].freeze
  MIN_TYPED_PRODUCTION_LENGTH = 40
  ADAPTIVE_ATTEMPT_KINDS = %w[retry rephrase follow_up compression extension].freeze
  REQUIRED_MOCK_COMPLETED_STATES = %w[scheduled mastered revealed].freeze

  before_action :load_arcade_session, only: %i[show attempt finish]

  def show
    @builder = EnglishArcadeSessionBuilder.new
    @targets = @builder.targets
    @modes = @builder.modes
    @selected_target = @arcade_session&.target || @builder.normalize_target(params[:target].presence || cockpit_session[:english_arcade_target])
    @selected_mode = @arcade_session&.mode || @builder.normalize_mode(params[:mode].presence || cockpit_session[:english_arcade_mode])
    @history = recent_attempts
    @schedule_summary = schedule_summary
    @progress_30_days = progress_30_days
    @thirty_day_plan = @builder.thirty_day_plan

    if @arcade_session
      expire_if_needed
      @plan = @builder.call(
        target: @arcade_session.target,
        mode: @arcade_session.mode,
        learner_key: learner_key,
        session: @arcade_session
      )
      requested_attempt = @arcade_session.english_arcade_attempts.find_by(id: params[:attempt_id])
      @pending_attempt = requested_attempt unless requested_attempt&.feedback_revealed?
      @feedback_attempt = requested_attempt if requested_attempt&.feedback_revealed?
      @exercise = session_exercise
      server_card = scheduled_card
      @current_card = if @pending_attempt
        @builder.frozen_card_for_attempt(@pending_attempt, session: @arcade_session)
      else
        server_card || requested_card || @plan.cards.first
      end
      @feedback_card = requested_attempt && @builder.card_for(
        target: @arcade_session.target,
        card_key: requested_attempt.card_key,
        session: @arcade_session,
        variant_id: requested_attempt.variant_key
      )
      @exercise = attempt_kind_for_variant(@current_card&.variant_id) if @current_card
      raw_feedback = @feedback_attempt&.diagnostic_evidence&.fetch("feedback", nil)
      feedback_contract = @feedback_attempt&.diagnostic_evidence&.fetch("assessment", nil) || @feedback_card&.variant_contract
      @feedback = if raw_feedback
        EnglishArcadeAttemptContract.public_feedback(feedback_contract || {}, feedback: raw_feedback)
      end
      @feynman_dto = if @pending_attempt && @current_card
        EnglishArcadeAttemptContract.public_feynman_dto(@current_card.variant_contract)
      end
      @mock_phase = current_mock_phase
      @mock_phase_payload = mock_phase_payload
    end

    respond_to do |format|
      format.html
      format.json do
        public_payload = {
          session_id: @arcade_session&.id,
          target: @selected_target,
          mode: @selected_mode,
          # A session JSON response exposes only the currently active contract;
          # the public 30-day plan carries ids and metadata, never future
          # prompts or retry challenges.
          cards: @current_card ? [ public_prompt_snapshot(@current_card) ] : [],
          feedback_revealed: @feedback_attempt&.feedback_revealed? || false,
          feedback: (@feedback_attempt&.feedback_revealed? ? @feedback : nil),
          mock: @mock_phase_payload,
          schedule: @schedule_summary,
          progress_30_days: @progress_30_days,
          thirty_day_plan: public_thirty_day_plan
        }
        public_payload[:feynman] = @feynman_dto if @pending_attempt
        render json: public_payload
      end
    end
  end

  def create
    # Keep the helper-compatible route resilient while older route manifests
    # still point the attempts collection at `create` instead of `attempt`.
    # The explicit attempt route is preferred; this branch prevents a posted
    # answer from accidentally opening a new mixed session during a deploy.
    if params[:english_arcade_attempt].present?
      load_arcade_session
      return attempt
    end

    @builder = EnglishArcadeSessionBuilder.new
    payload = session_payload
    raw_target = payload[:target].presence || params.dig(:english_arcade_session, :target) || params[:target]
    raw_mode = payload[:mode].presence || params.dig(:english_arcade_session, :mode) || params[:mode]
    target = @builder.normalize_target(raw_target)
    mode = @builder.normalize_mode(raw_mode)
    requested_card_key = payload[:card_key].to_s.presence
    requested_mock_id = payload[:mock_id].to_s.presence
    exercise = normalize_attempt_kind(payload[:exercise])
    parent_attempt = nil
    required_card_keys = []
    mock_spec = nil

    if requested_mock_id
      mock_spec = EnglishArcadeCurriculum.mock(requested_mock_id)
      return reject_mock_launch("That mock is not registered on the server.", target: target, mode: mode) unless mock_spec
      return reject_mock_launch("A mock can only start with the initial exercise.", target: target, mode: mode) if payload[:exercise].present? && payload[:exercise].to_s.downcase != "initial"

      expected_target = mock_spec.fetch("target")
      expected_mode = mock_spec.fetch("mode")
      if payload[:target].present? && @builder.normalize_target(payload[:target]) != expected_target
        return reject_mock_launch("The selected target does not match this mock.", target: target, mode: mode)
      end
      if payload[:mode].present? && @builder.normalize_mode(payload[:mode]) != expected_mode
        return reject_mock_launch("The selected mode does not match this mock.", target: target, mode: mode)
      end

      target = expected_target
      mode = expected_mode
      required_card_keys = Array(mock_spec.fetch("required_card_keys"))
      expected_first_key = required_card_keys.first
      if requested_card_key.present? && requested_card_key != expected_first_key
        return reject_mock_launch("The launch card must be the first card in this mock.", target: target, mode: mode)
      end
      requested_card_key = expected_first_key
      missing_card = required_card_keys.find { |card_key| @builder.card_for(target: target, card_key: card_key, variant_id: "initial").nil? }
      return reject_mock_launch("This mock references a card that is not available.", target: target, mode: mode) if missing_card
    else
      if requested_card_key.blank? && ADAPTIVE_ATTEMPT_KINDS.include?(exercise)
        return redirect_to english_arcade_path(target: target, mode: mode), alert: "Choose a canonical card before starting an adaptation."
      end
      if requested_card_key
        curriculum_target = EnglishArcadeCurriculum.target_for(requested_card_key)
        unless selectable_pack_target?(curriculum_target) && @builder.card_for(target: curriculum_target, card_key: requested_card_key, variant_id: @builder.variant_id_for(exercise))
          return redirect_to english_arcade_path(target: target, mode: mode), alert: "That curriculum item is not a canonical launchable card."
        end

        # A curriculum launcher is authoritative for its card target. This avoids
        # a stale radio selection silently opening a different pack.
        target = curriculum_target
      end
      if ADAPTIVE_ATTEMPT_KINDS.include?(exercise)
        parent_attempt = latest_eligible_adaptive_parent(target: target, card_key: requested_card_key, kind: exercise)
        return redirect_to english_arcade_path(target: target, mode: mode), alert: "The latest revealed attempt for this card must be correct or have a completed Black Box before adaptation." unless parent_attempt
      end
      # Preserve the legacy ordered General flow for already-created links, but
      # it deliberately has no mock_id and therefore cannot satisfy a gate.
      required_card_keys = if exercise == "initial" && target == "general" && mode == "timed_30" && requested_card_key.in?(EnglishArcadeCurriculum::GENERAL_FINAL_MOCK_ITEM_IDS)
        EnglishArcadeCurriculum::GENERAL_FINAL_MOCK_ITEM_IDS
      else
        []
      end
    end
    now = Time.current
    duration = @builder.modes.fetch(mode).fetch(:duration_seconds)
    content_probe = requested_card_key && @builder.card_for(
      target: target == "interview" ? (EnglishArcadeCurriculum.target_for(requested_card_key) || target) : target,
      card_key: requested_card_key,
      variant_id: @builder.variant_id_for(exercise)
    )

    metadata = {
      "source" => "english_arcade_launcher",
      "content_source" => @builder.call(target: target, mode: mode, learner_key: learner_key, limit: 1).source,
      "target_key" => target,
      "mode" => mode,
      "exercise" => exercise,
      "required_card_keys" => required_card_keys,
      "scheduled_card_key" => required_card_keys.any? ? nil : requested_card_key,
      "parent_attempt_id" => parent_attempt&.id,
      "content_version" => content_probe&.content_version.to_s.presence || "unknown",
      "contract_version" => EnglishArcadeAttemptContract::CONTRACT_VERSION,
      "active_variant_id" => @builder.variant_id_for(exercise)
    }
    if mock_spec
      metadata.merge!(
        "mock_id" => mock_spec.fetch("id"),
        "curriculum_day" => mock_spec.fetch("day"),
        "required_card_keys" => required_card_keys,
        "scheduled_card_key" => nil
      )
      metadata["phase_state"] = initial_phase_state(mock_spec, now) if mock_phases_required?(mock_spec)
    end

    @arcade_session = EnglishArcadeSession.create!(
      learner_key: learner_key,
      target: target,
      mode: mode,
      duration_seconds: duration,
      started_at: now,
      expires_at: now + duration.seconds,
      metadata: metadata
    )
    persist_launcher_choice(target, mode)

    redirect_to english_arcade_path(session_id: @arcade_session.id), status: :see_other
  rescue ActiveRecord::RecordInvalid => error
    redirect_to english_arcade_path(target: target, mode: mode), alert: error.record.errors.full_messages.to_sentence
  end

  def attempt
    unless @arcade_session
      return redirect_to english_arcade_path, alert: "Start a session before answering."
    end

    payload = attempt_payload
    pending_attempt = @arcade_session.english_arcade_attempts.find_by(id: payload[:attempt_id])

    if @arcade_session.expired?(at: Time.current) && payload[:phase].to_s == "mock_phase"
      @arcade_session.expire!
      return reject_mock_phase("This mock session has ended.")
    end
    if @arcade_session.expired?(at: Time.current) && !pending_attempt
      @arcade_session.expire!
      return redirect_to english_arcade_path(session_id: @arcade_session.id), alert: "This timed session has ended."
    end

    @builder = EnglishArcadeSessionBuilder.new

    return complete_mock_phase(payload) if payload[:phase].to_s == "mock_phase"
    return finalize_attempt(pending_attempt, payload) if payload[:phase].to_s == "feynman" && pending_attempt
    return save_postmortem(pending_attempt, payload) if payload[:phase].to_s == "postmortem" && pending_attempt

    commit_attempt(payload)
  rescue ActiveRecord::RecordInvalid => error
    redirect_to english_arcade_path(session_id: @arcade_session.id), alert: error.record.errors.full_messages.to_sentence
  end

  def commit_attempt(payload)
    kind = normalize_attempt_kind(payload[:exercise].presence || session_exercise)
    card = if required_mock_card_keys.any?
      required_mock_next_card(payload)
    else
      scheduled_or_requested_card(payload)
    end
    return unless card
    return redirect_to english_arcade_path(session_id: @arcade_session.id), alert: "That question is no longer available." unless card

    requested_status = payload[:answer_status].presence || payload[:outcome].presence
    requested_status ||= payload[:phase] if RESET_STATUSES.include?(payload[:phase].to_s)
    requested_status = "skip" if payload[:skip].to_s == "1"
    answer_status = normalize_answer_status(requested_status)
    typed_answer = payload[:typed_answer].to_s.truncate(4_000, omission: "…")
    if RESET_STATUSES.include?(answer_status) && payload[:answer_choice].blank? && typed_answer.blank?
      typed_answer = "[#{answer_status}]"
    end
    return reject_typed_production if !RESET_STATUSES.include?(answer_status) && typed_answer.strip.length < MIN_TYPED_PRODUCTION_LENGTH
    parent_attempt = adaptive_parent_for(card, kind, explicit_parent_id: payload[:parent_attempt_id])
    return reject_adaptive_parent if ADAPTIVE_ATTEMPT_KINDS.include?(kind) && !parent_attempt
    critical_artifact = EnglishArcadeAttemptContract.artifact_from(
      payload,
      critical_thinking: card.critical_thinking.to_h
    )
    grade = if answer_status == "skip" || answer_status == "error"
      OpenStruct.new(
        correct: false,
        feedback: card.feedback,
        diagnostic_evidence: {
          "target" => card.target,
          "card_key" => card.key,
          "correct" => false,
          "signal" => "#{answer_status}-without-assessment",
          "assessment" => EnglishArcadeAttemptContract.frozen_contract(card.variant_contract, content_version: card.content_version)
            .merge(
              "variant_id" => card.variant_id,
              "variant_digest" => card.variant_digest,
              "content_version" => card.content_version
            )
        }
      )
    else
      @builder.grade(card: card, answer_choice: payload[:answer_choice], typed_answer: typed_answer)
    end
    # Validate the typed critical ledger only after the server has validated
    # the opaque answer token. Every assessable 1.4 contract variant must
    # capture the ledger before a row or schedule can be created. Skip/reset
    # paths remain available as non-eligible practice records.
    if !RESET_STATUSES.include?(answer_status) && answer_status != "error" && !critical_artifact.fetch("complete")
      return reject_critical_artifact(critical_artifact.fetch("missing"))
    end
    production = begin
      production_evidence_from(payload, typed_answer)
    rescue InvalidSelfRubric
      return reject_self_rubric
    end
    now = Time.current

    attempt = nil
    EnglishArcadeSession.transaction do
      schedule = @builder.schedule_for(card: card, learner_key: learner_key, on: now.to_date)
      schedule.with_lock do
        box_before = schedule.box
        diagnostic = grade.diagnostic_evidence.merge(
          "contract_version" => EnglishArcadeAttemptContract::CONTRACT_VERSION,
          "captured_at" => now.iso8601(6),
          "attempt_kind" => kind,
          "response_ms" => integer_or_nil(payload[:response_ms]),
          "state" => "feynman",
          "answer_status" => answer_status,
          "outcome" => answer_status,
          "production" => production,
          "self_ratings" => production.fetch("self_rubric"),
          "critical_artifact" => critical_artifact,
          "artifacts" => {
            "problem_frame" => critical_artifact.fetch("problem_frame", ""),
            "evidence_ledger" => critical_artifact.fetch("learner_classifications", {}),
            "source_quality" => critical_artifact.fetch("source_quality", ""),
            "comparison" => critical_artifact.fetch("comparison", {}),
            "counterexample" => critical_artifact.fetch("counterexample", ""),
            "certainty" => {
              "confidence_percent" => critical_artifact["confidence_percent"],
              "change_my_mind" => critical_artifact.fetch("change_my_mind", "")
            }
          },
          "active_variant_id" => card.variant_id,
          "active_variant_digest" => card.variant_digest,
          "content_version" => card.content_version,
          "lengths" => {
            "typed_answer" => typed_answer.to_s.strip.length,
            "critical_artifact_complete" => critical_artifact.fetch("complete")
          },
          "server_checks" => {
            "opaque_answer_token" => true,
            "variant_bound" => true,
            "content_frozen" => true,
            "self_ratings_gate_eligible" => false
          },
          "assessment_scope" => "server_contract",
          "source" => "authored_contract"
        )
        attempt = @arcade_session.english_arcade_attempts.create!(
          learner_key: learner_key,
          target: card.target,
          card_key: card.key,
          attempt_kind: kind,
          parent_attempt: parent_attempt,
          answer_choice: payload[:answer_choice].to_s.strip.presence,
          typed_answer: typed_answer.presence,
          correct: grade.correct,
          feedback_revealed: false,
          state: "feynman",
          variant_key: card.variant_id,
          quality_score: 0,
          response_ms: integer_or_nil(payload[:response_ms]),
          box_before: box_before,
          box_after: box_before,
          next_due_on: nil,
          answered_at: now,
          diagnostic_evidence: diagnostic,
          prompt_snapshot: @builder.prompt_snapshot(card)
        )
      end
      @arcade_session.update!(
        question_count: @arcade_session.question_count + 1,
        score: @arcade_session.score,
        metadata: commit_metadata_for(attempt, card, kind)
      )
    end

    respond_to do |format|
      format.html do
        redirect_to english_arcade_path(
          session_id: @arcade_session.id,
          attempt_id: attempt.id,
          card_key: card.key,
          exercise: kind,
          phase: "feynman"
        ), status: :see_other
      end
      format.json do
        render json: {
          attempt_id: attempt.id,
          state: attempt.state,
          feedback_revealed: attempt.feedback_revealed,
          box_before: attempt.box_before,
          feynman: EnglishArcadeAttemptContract.public_feynman_dto(card.variant_contract)
        }, status: :created
      end
    end
  rescue EnglishArcadeAttemptContract::InvalidChoice
    reject_invalid_choice
  end

  def finalize_attempt(pending_attempt, payload)
    return redirect_to english_arcade_path(session_id: @arcade_session.id), alert: "That attempt is already revealed." if pending_attempt.feedback_revealed?

    assessment = pending_attempt.diagnostic_evidence.to_h.fetch("assessment", {}).to_h
    return reject_frozen_contract(pending_attempt) unless assessment["variant_digest"].to_s.present? && assessment["correct_choice"].to_s.present?

    # The card is used only for scheduling and redirect metadata. Grading and
    # feedback always come from the frozen assessment committed before reveal.
    card = @builder.card_for(
      target: @arcade_session.target,
      card_key: pending_attempt.card_key,
      session: @arcade_session,
      variant_id: assessment["variant_id"].presence || pending_attempt.variant_key
    )
    feynman_text = payload[:feynman_text].to_s.truncate(4_000, omission: "…")
    return reject_feynman(pending_attempt) if feynman_text.strip.length < MIN_TYPED_PRODUCTION_LENGTH

    answer_status = normalize_answer_status(pending_attempt.diagnostic_evidence["answer_status"] || pending_attempt.diagnostic_evidence["outcome"])
    effective_correct = assessment["correct"] == true && !RESET_STATUSES.include?(answer_status)
    frozen_feedback = EnglishArcadeAttemptContract.public_feedback(
      assessment,
      feedback: assessment.fetch("feedback", {})
    ).merge(
      "answer" => assessment["answer_text"],
      "selected" => pending_attempt.diagnostic_evidence["selected_option"],
      "frozen_content_version" => assessment["content_version"]
    )
    # Evidence provenance is reveal-only and is frozen in server-owned session
    # metadata at commit. It is never read from a freshly loaded/mutated pack.
    frozen_reveal = @arcade_session.metadata.to_h.deep_stringify_keys.dig("frozen_reveal_contracts", pending_attempt.id.to_s).to_h
    frozen_feedback.merge!(
      "sources" => frozen_reveal["sources"],
      "provenance" => frozen_reveal["provenance"]
    ) if frozen_reveal.any?
    now = Time.current
    EnglishArcadeSession.transaction do
      schedule = if card
        @builder.schedule_for(card: card, learner_key: learner_key, on: now.to_date)
      else
        EnglishArcadeCard.find_or_initialize_by(learner_key: learner_key, target: pending_attempt.target, card_key: pending_attempt.card_key).tap do |record|
          record.due_on ||= now.to_date
          record.interval_days ||= EnglishArcadeCard::BOX_INTERVALS.fetch(record.box || 1)
          record.box ||= 1
          record.save! if record.new_record? || record.changed?
        end
      end
      schedule.with_lock do
        schedule.record!(correct: true, at: now) if effective_correct
        # A wrong reveal persists at feedback until the required Black Box
        # reflection is submitted; only then does it become scheduled.
        state = effective_correct ? "scheduled" : "feedback"
        diagnostic = pending_attempt.diagnostic_evidence.merge(
          "feedback" => frozen_feedback,
          "feynman_present" => true,
          "feynman_length" => feynman_text.length,
          "state" => state,
          "black_box_required" => !effective_correct,
          "reveal_source" => "committed_frozen_contract",
          "assessment_scope" => "server_contract"
        )
        pending_attempt.update!(
          state: state,
          feedback_revealed: true,
          correct: effective_correct,
          quality_score: quality_score_for(pending_attempt, effective_correct, feynman_text: feynman_text),
          feynman_text: feynman_text.presence,
          box_after: effective_correct ? schedule.box : schedule.box,
          next_due_on: effective_correct ? schedule.due_on : nil,
          answered_at: pending_attempt.answered_at || now,
          diagnostic_evidence: diagnostic
        )
      end
      @arcade_session.update!(score: @arcade_session.score + (effective_correct ? 100 : 0))
    end

    respond_to do |format|
      format.html do
        redirect_to english_arcade_path(
          session_id: @arcade_session.id,
          attempt_id: pending_attempt.id,
          card_key: pending_attempt.card_key,
          exercise: pending_attempt.attempt_kind
        ), status: :see_other
      end
      format.json do
        render json: {
          attempt_id: pending_attempt.id,
          state: pending_attempt.state,
          correct: pending_attempt.correct,
          feedback_revealed: pending_attempt.feedback_revealed,
          feedback: pending_attempt.diagnostic_evidence.fetch("feedback"),
          box_before: pending_attempt.box_before,
          box_after: pending_attempt.box_after,
          next_due_on: pending_attempt.next_due_on,
          next_interval: effective_correct ? EnglishArcadeCard.find_by(learner_key: learner_key, target: pending_attempt.target, card_key: pending_attempt.card_key)&.interval_label : nil,
          black_box_required: !effective_correct
        }, status: :ok
      end
    end
  end

  def save_postmortem(attempt, payload)
    return redirect_to english_arcade_path(session_id: @arcade_session.id), alert: "Reveal feedback before saving a post-mortem." unless attempt&.feedback_revealed?
    unless %w[feedback black_box].include?(attempt.state) && attempt.diagnostic_evidence["black_box_required"] == true
      return reject_postmortem(attempt, [ "not_required" ])
    end

    fields = black_box_fields_from(payload)
    missing = fields.filter_map { |field, value| field unless actionable_black_box_value?(value) }
    return reject_postmortem(attempt, missing) if missing.any?

    card = @builder.card_for(target: @arcade_session.target, card_key: attempt.card_key)
    return redirect_to english_arcade_path(session_id: @arcade_session.id), alert: "That question is no longer available." unless card

    now = Time.current
    schedule = nil
    EnglishArcadeSession.transaction do
      schedule = @builder.schedule_for(card: card, learner_key: learner_key, on: now.to_date)
      schedule.with_lock do
        schedule.record!(correct: false, at: now)
        attempt.update!(
          black_box_root_cause: fields.fetch("root_cause"),
          black_box_missing_signal: fields.fetch("missing_signal"),
          black_box_preventive_rule: fields.fetch("preventive_rule"),
          black_box_targeted_exercise: fields.fetch("targeted_exercise"),
          black_box_retest_dates: fields.fetch("retest_dates"),
          black_box_symptom: payload[:black_box_symptom].to_s.truncate(4_000, omission: "…").presence,
          black_box_expected: payload[:black_box_expected].to_s.truncate(4_000, omission: "…").presence,
          black_box_actual: payload[:black_box_actual].to_s.truncate(4_000, omission: "…").presence,
          black_box_repair: payload[:black_box_repair].to_s.truncate(4_000, omission: "…").presence,
          # Keep the legacy column as a compact audit label, but never use it as
          # a substitute for the five actionable fields above.
          postmortem_text: fields.values.join("\n\n").truncate(4_000, omission: "…"),
          state: "scheduled",
          box_after: schedule.box,
          next_due_on: schedule.due_on,
          diagnostic_evidence: attempt.diagnostic_evidence.merge(
            "black_box_postmortem_present" => true,
            "black_box_fields" => fields,
            "state" => "scheduled"
          )
        )
      end
    end
    respond_to do |format|
      format.html do
        redirect_to english_arcade_path(session_id: @arcade_session.id, attempt_id: attempt.id, card_key: attempt.card_key), status: :see_other
      end
      format.json do
        render json: {
          attempt_id: attempt.id,
          state: attempt.state,
          black_box_required: false,
          black_box_fields: attempt.black_box_fields,
          box_after: attempt.box_after,
          next_due_on: attempt.next_due_on,
          next_interval: schedule&.interval_label
        }, status: :ok
      end
    end
  end

  def complete_mock_phase(payload)
    spec = session_mock_spec
    return reject_mock_phase("This session has no curriculum-owned phases.") unless mock_phases_required?(spec)
    if !@arcade_session.active? || @arcade_session.expired?(at: Time.current)
      @arcade_session.expire! if @arcade_session.active?
      return reject_mock_phase("This mock session has ended.")
    end

    phases = Array(spec.fetch("phases"))
    metadata = @arcade_session.metadata.deep_stringify_keys
    state = metadata["phase_state"].is_a?(Hash) ? metadata["phase_state"].deep_stringify_keys : {}
    index = state["current_index"].to_i
    return reject_mock_phase("Every phase in this mock is already complete.") if index >= phases.length

    expected = phases.fetch(index)
    return reject_mock_phase("Complete the current phase before changing phase order.") unless payload[:phase_id].to_s == expected.fetch("id")

    artifact = payload[:phase_artifact].to_s.truncate(8_000, omission: "…").strip
    minimum = expected.fetch("minimum_chars").to_i
    return reject_mock_phase("Write at least #{minimum} characters for this phase artifact.") if artifact.length < minimum

    checkpoints = Array(state["checkpoints"])
    return reject_mock_phase("The phase ledger is not in the expected order.") unless checkpoints.length == index
    return reject_mock_phase("The phase ledger failed its server-side integrity check.") unless valid_phase_prefix?(spec, state, now: Time.current)

    started_at = parse_phase_time(state["current_phase_started_at"])
    now = Time.current
    return reject_mock_phase("The server has not started this phase.") unless started_at

    elapsed = now - started_at
    required_seconds = EnglishArcadeCurriculum.minimum_phase_seconds(expected)
    return reject_mock_phase("This phase cannot be completed before 90% of its #{expected.fetch('minutes')}-minute timebox.") if elapsed < required_seconds

    checkpoint = {
      "phase_id" => expected.fetch("id"),
      "phase_index" => index,
      "started_at" => started_at.iso8601(6),
      "completed_at" => now.iso8601(6),
      "elapsed_seconds" => elapsed.round(3),
      "artifact" => artifact,
      "artifact_length" => artifact.length
    }
    next_index = index + 1
    next_state = {
      "current_index" => next_index,
      "current_phase_started_at" => next_index < phases.length ? now.iso8601(6) : nil,
      "completed_at" => next_index == phases.length ? now.iso8601(6) : nil,
      "checkpoints" => checkpoints + [ checkpoint ]
    }

    @arcade_session.with_lock do
      current_metadata = @arcade_session.reload.metadata.deep_stringify_keys
      current_state = current_metadata["phase_state"].is_a?(Hash) ? current_metadata["phase_state"].deep_stringify_keys : {}
      return reject_mock_phase("The mock phase changed; reload before submitting again.") unless current_state == state

      @arcade_session.update!(metadata: current_metadata.merge("phase_state" => next_state))
    end

    respond_to do |format|
      format.html { redirect_to english_arcade_path(session_id: @arcade_session.id), notice: "Phase #{index + 1} recorded. Continue with the next interviewer brief." }
      format.json do
        render json: {
          phase_id: expected.fetch("id"),
          phase_index: index,
          elapsed_seconds: elapsed.round(3),
          current_phase: phase_payload(spec, next_state)
        }, status: :ok
      end
    end
  end

  def finish
    return redirect_to english_arcade_path unless @arcade_session
    if @arcade_session.active? && @arcade_session.expired?(at: Time.current)
      @arcade_session.expire!
      return redirect_to english_arcade_path(session_id: @arcade_session.id), alert: "This session has expired; its committed evidence was saved without completing the mock."
    end
    if session_mock_id.present?
      unless mock_session_compatible? && EnglishArcadeMockEvidence.qualifying?(session: @arcade_session, now: Time.current)
        return redirect_to english_arcade_path(session_id: @arcade_session.id), alert: "Complete the exact mock sequence, reveal each Feynman answer, and spend at least 90% of the timed window before finishing."
      end
    elsif required_mock_card_keys.any? && !required_mock_completion_complete?
      return redirect_to english_arcade_path(session_id: @arcade_session.id), alert: "Complete every required card in order before finishing this mock."
    end

    @arcade_session.complete! unless @arcade_session.completed? || @arcade_session.expired?
    redirect_to english_arcade_path(session_id: @arcade_session.id), notice: "Session saved. Review the diagnostic evidence below."
  end

  private

  def load_arcade_session
    @arcade_session = EnglishArcadeSession.find_by(id: params[:session_id], learner_key: learner_key)
  end

  def cockpit_session
    session
  end

  def learner_key
    # Basic auth is the cockpit's only identity boundary today. Never persist a
    # password; an anonymous fallback keeps local development and tests useful.
    request.get_header("REMOTE_USER").presence || ENV["STUDY_COCKPIT_USERNAME"].presence || "anonymous"
  end

  def public_prompt_snapshot(card)
    @builder.prompt_snapshot(card).except("variant_digest")
  end

  def session_payload
    source = params[:english_arcade_session]
    source.respond_to?(:permit) ? source.permit(:target, :mode, :card_key, :exercise, :mock_id) : params.permit(:target, :mode, :card_key, :exercise, :mock_id)
  end

  def attempt_payload
    params.fetch(:english_arcade_attempt, params).permit(
      :card_key, :answer_choice, :typed_answer, :response_ms, :attempt_id, :parent_attempt_id, :exercise,
      :phase, :feynman_text,
      :answer_status, :outcome, :postmortem_text, :black_box_root_cause,
      :black_box_missing_signal, :black_box_preventive_rule,
      :black_box_targeted_exercise, :black_box_retest_dates,
      :black_box_symptom, :black_box_expected, :black_box_actual, :black_box_repair,
      :skip, :english_directness, :self_clarity, :self_precision,
      :self_naturalness, :self_pragmatic_appropriateness, :self_technical_correctness,
      :phase_id, :phase_artifact,
      *EnglishArcadeAttemptContract::ARTIFACT_FIELDS
    )
  end

  def persist_launcher_choice(target, mode)
    cockpit_session[:english_arcade_target] = target
    cockpit_session[:english_arcade_mode] = mode
  end

  def requested_card
    return if adaptive_session? || required_mock_card_keys.any?
    return unless params[:card_key].present?

    @builder.card_for(
      target: @arcade_session.target,
      card_key: params[:card_key],
      session: @arcade_session,
      variant_id: @builder.variant_id_for(session_exercise)
    )
  end

  def recent_attempts
    scope = EnglishArcadeAttempt.where(learner_key: learner_key)
    scope = scope.where(english_arcade_session: @arcade_session) if @arcade_session
    scope.recent_first.limit(8)
  end

  def schedule_summary
    cards = EnglishArcadeCard.for_learner(learner_key)
    {
      due: cards.due.count,
      learning: cards.where(box: 1..4).count,
      mastered: EnglishArcadeCard.mastered_keys_for(learner_key).length
    }
  end

  def expire_if_needed
    return unless @arcade_session.active? && @arcade_session.expired?(at: Time.current)

    @arcade_session.expire!
  end

  def normalize_attempt_kind(value)
    kind = value.to_s.downcase
    EnglishArcadeAttempt::ATTEMPT_KINDS.include?(kind) ? kind : "initial"
  end

  def attempt_kind_for_variant(variant_id)
    case variant_id.to_s
    when "delayed_variant" then "retry"
    when "follow_up", "rephrase", "compression", "extension" then variant_id.to_s
    else "initial"
    end
  end

  def adaptive_parent_for(card, kind, explicit_parent_id: nil)
    return nil unless ADAPTIVE_ATTEMPT_KINDS.include?(kind)

    metadata = @arcade_session.metadata.deep_stringify_keys
    server_parent_id = metadata["parent_attempt_id"].presence || metadata["active_parent_attempt_id"].presence
    # The parent is server-owned launch state. A client-supplied id is kept in
    # the request only for backwards-compatible form parsing and is never
    # allowed to replace or invalidate the authoritative parent.

    parent_id = server_parent_id
    candidate = EnglishArcadeAttempt.find_by(id: parent_id)
    return unless EnglishArcadeEvidenceEligibility.adaptation_parent?(
      candidate,
      learner_key: learner_key,
      target: card.target,
      card_key: card.key,
      child_variant_id: card.variant_id,
      child_digest: card.variant_digest,
      kind: kind
    )

    candidate
  end

  def latest_eligible_adaptive_parent(target:, card_key:, kind: "follow_up")
    variant_id = @builder.variant_id_for(kind)
    candidate_card = @builder.card_for(target: target, card_key: card_key, variant_id: variant_id)
    return unless candidate_card
    candidates = EnglishArcadeAttempt.where(
      learner_key: learner_key,
      target: target,
      card_key: card_key,
      feedback_revealed: true
    ).recent_first.to_a
    if kind.to_s == "retry"
      # A delayed retry is anchored to the newest *eligible initial* attempt,
      # never to whichever adaptation happened to be revealed most recently.
      # The eligibility service also enforces the seven-day floor and digest
      # distinction, while this filter prevents a later follow-up/rephrase or
      # an ineligible recent initial from masking an older retention anchor.
      candidates.find do |candidate|
        candidate.attempt_kind.to_s == "initial" &&
          EnglishArcadeEvidenceEligibility.adaptation_parent?(
            candidate,
            learner_key: learner_key,
            target: target,
            card_key: card_key,
            child_variant_id: candidate_card.variant_id,
            child_digest: candidate_card.variant_digest,
            kind: kind
          )
      end
    else
      # Same-lineage follow-ups retain the legacy latest-parent behavior: a
      # newer failed/incomplete initial is an explicit repair signal and must
      # not silently fall back to an older answer.
      candidate = candidates.first
      return unless candidate&.attempt_kind.to_s == "initial"

      EnglishArcadeEvidenceEligibility.adaptation_parent?(
        candidate,
        learner_key: learner_key,
        target: target,
        card_key: card_key,
        child_variant_id: candidate_card.variant_id,
        child_digest: candidate_card.variant_digest,
        kind: kind
      ) ? candidate : nil
    end
  end

  def adaptive_session?
    ADAPTIVE_ATTEMPT_KINDS.include?(session_exercise)
  end

  def session_exercise
    normalize_attempt_kind(@arcade_session.metadata.fetch("exercise", "initial"))
  end

  def scheduled_card
    return if required_mock_card_keys.any?

    key = @arcade_session.metadata["scheduled_card_key"].presence
    return unless key

    @builder.card_for(
      target: @arcade_session.target,
      card_key: key,
      session: @arcade_session,
      variant_id: @builder.variant_id_for(session_exercise)
    )
  end

  def required_mock_card_keys
    Array(@arcade_session.metadata["required_card_keys"])
  end

  def session_mock_id
    @arcade_session.metadata["mock_id"].to_s.presence
  end

  def session_mock_spec
    return unless session_mock_id

    EnglishArcadeCurriculum.mock(session_mock_id)
  end

  def mock_phases_required?(spec = session_mock_spec)
    spec.is_a?(Hash) && Array(spec["phases"]).any?
  end

  def initial_phase_state(spec, now)
    {
      "current_index" => 0,
      "current_phase_started_at" => now.iso8601(6),
      "completed_at" => nil,
      "checkpoints" => []
    }
  end

  def current_mock_phase
    spec = session_mock_spec
    return unless mock_phases_required?(spec)

    state = @arcade_session.metadata["phase_state"]
    return unless state.is_a?(Hash) && state.key?("current_index")

    phases = Array(spec.fetch("phases"))
    phases[state["current_index"].to_i]
  end

  def mock_phase_payload
    spec = session_mock_spec
    return unless mock_phases_required?(spec)

    state = @arcade_session.metadata["phase_state"]
    return unless state.is_a?(Hash) && state.key?("current_index")

    phase_payload(spec, state)
  end

  def phase_payload(spec, state)
    state = state.is_a?(Hash) ? state.deep_stringify_keys : {}
    phases = Array(spec.fetch("phases"))
    index = state["current_index"].to_i
    phase = phases[index]
    {
      "mock_id" => spec.fetch("id"),
      "target" => spec.fetch("target"),
      "phase_index" => index,
      "phase_count" => phases.length,
      "status" => phase ? "active" : "complete",
      "completed_phase_ids" => Array(state["checkpoints"]).filter_map { |checkpoint| checkpoint["phase_id"] },
      "current_phase" => phase
    }
  end

  def mock_phases_complete?
    spec = session_mock_spec
    return true unless mock_phases_required?(spec)

    EnglishArcadeCurriculum.phase_state_valid?(
      spec,
      @arcade_session.metadata["phase_state"],
      session_started_at: @arcade_session.started_at,
      expires_at: @arcade_session.expires_at,
      now: @arcade_session.finished_at || Time.current
    )
  end

  def valid_phase_prefix?(spec, state, now: Time.current)
    state = state.is_a?(Hash) ? state.deep_stringify_keys : {}
    phases = Array(spec.fetch("phases"))
    index = state["current_index"].to_i
    checkpoints = Array(state["checkpoints"])
    return false unless @arcade_session.expires_at
    return false unless index.between?(0, phases.length) && checkpoints.length == index

    previous_completed_at = nil
    checkpoints.each_with_index.all? do |checkpoint, checkpoint_index|
      phase = phases.fetch(checkpoint_index)
      started_at = parse_phase_time(checkpoint["started_at"])
      completed_at = parse_phase_time(checkpoint["completed_at"])
      artifact = checkpoint["artifact"].to_s.strip
      valid = checkpoint["phase_id"].to_s == phase.fetch("id") &&
        checkpoint["phase_index"].to_i == checkpoint_index &&
        artifact.length >= phase.fetch("minimum_chars").to_i &&
        checkpoint["artifact_length"].to_i == artifact.length &&
        started_at && completed_at &&
        (completed_at - started_at) >= EnglishArcadeCurriculum.minimum_phase_seconds(phase) &&
        completed_at <= now &&
        completed_at <= @arcade_session.expires_at &&
        started_at >= @arcade_session.started_at &&
        started_at <= @arcade_session.expires_at &&
        (checkpoint["elapsed_seconds"].to_f - (completed_at - started_at)).abs < 1.0 &&
        (previous_completed_at.nil? || started_at >= previous_completed_at)
      previous_completed_at = completed_at if valid
      valid
    end && current_phase_started_at_valid?(state, phases, index, previous_completed_at)
  end

  def current_phase_started_at_valid?(state, phases, index, previous_completed_at)
    started_at = parse_phase_time(state["current_phase_started_at"])
    return started_at.nil? if index == phases.length

    if index.zero?
      session_started_at = @arcade_session.started_at
      return started_at && session_started_at && (started_at - session_started_at).abs < 1.0
    end

    index < phases.length && started_at && previous_completed_at && started_at >= previous_completed_at
  end

  def parse_phase_time(value)
    return if value.blank?

    Time.iso8601(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def mock_session_compatible?
    spec = session_mock_spec
    return false unless spec

    @arcade_session.target == spec.fetch("target") &&
      @arcade_session.mode == spec.fetch("mode") &&
      @arcade_session.duration_seconds.to_i == spec.fetch("duration_minutes").to_i * 60 &&
      @arcade_session.metadata["curriculum_day"].to_i == spec.fetch("day") &&
      @arcade_session.metadata["exercise"].to_s == "initial" &&
      @arcade_session.metadata.key?("scheduled_card_key") &&
      @arcade_session.metadata["scheduled_card_key"].nil? &&
      Array(@arcade_session.metadata["required_card_keys"]) == Array(spec.fetch("required_card_keys")) &&
      @arcade_session.metadata["content_version"].to_s.present? && @arcade_session.metadata["content_version"].to_s != "unknown"
  end

  def mock_elapsed_sufficient?
    started_at = @arcade_session.started_at
    duration_seconds = @arcade_session.duration_seconds.to_f
    return false unless started_at && duration_seconds.positive?

    elapsed = (@arcade_session.finished_at || Time.current) - started_at
    elapsed >= (duration_seconds.to_i * 9 / 10)
  end

  def required_mock_next_card(payload)
    return if required_mock_card_keys.empty?
    return reject_required_mock_incomplete if required_mock_incomplete_attempt?

    spec = session_mock_spec
    sequence = if spec
      Array(spec["required_sequence"])
    else
      # Legacy timed General links predate curriculum-owned mock ids. Their
      # metadata still carries an authoritative ordered card list, so derive
      # the same one-pass initial sequence instead of treating the session as
      # an invalid modern mock.
      required_mock_card_keys.each_with_index.map do |card_key, index|
        {
          "step" => index,
          "card_key" => card_key,
          "attempt_kind" => "initial",
          "variant_id" => "initial",
          "content_variant_id" => "initial",
          "parent_step" => nil
        }
      end
    end
    index = @arcade_session.english_arcade_attempts.count
    expected_step = sequence[index]
    return reject_required_mock_card unless expected_step
    expected_target = EnglishArcadeCurriculum.target_for(expected_step.fetch("card_key"))
    expected = @builder.card_for(
      target: expected_target,
      card_key: expected_step.fetch("card_key"),
      session: @arcade_session,
      variant_id: expected_step["content_variant_id"].presence || expected_step.fetch("variant_id")
    )
    return reject_required_mock_card unless expected
    return reject_required_mock_card unless payload[:card_key].to_s == expected.key
    supplied_kind = normalize_attempt_kind(payload[:exercise].presence || "initial")
    return reject_required_mock_card unless supplied_kind == expected_step.fetch("attempt_kind")

    expected
  end

  def scheduled_or_requested_card(payload)
    key = @arcade_session.metadata["scheduled_card_key"].presence || payload[:card_key]
    @builder.card_for(
      target: @arcade_session.target,
      card_key: key,
      session: @arcade_session,
      variant_id: @builder.variant_id_for(payload[:exercise].presence || session_exercise)
    )
  end

  def reject_required_mock_card
    respond_to do |format|
      format.html { redirect_to english_arcade_path(session_id: @arcade_session.id), alert: "This timed mock only accepts its next required card." }
      format.json { render json: { error: "required_mock_card_only" }, status: :unprocessable_entity }
    end
    nil
  end

  def reject_mock_phase(message)
    respond_to do |format|
      format.html { redirect_to english_arcade_path(session_id: @arcade_session.id), alert: message }
      format.json { render json: { error: "invalid_mock_phase", message: message }, status: :unprocessable_entity }
    end
    nil
  end

  def reject_mock_launch(message, target:, mode:)
    respond_to do |format|
      format.html { redirect_to english_arcade_path(target: target, mode: mode), alert: message }
      format.json { render json: { error: "invalid_mock_launch", message: message }, status: :unprocessable_entity }
    end
    nil
  end

  def required_mock_incomplete_attempt?
    @arcade_session.english_arcade_attempts.where(card_key: required_mock_card_keys).to_a.any? do |attempt|
      !required_mock_attempt_complete?(attempt)
    end
  end

  # Completion is stricter than progression: a mock is only evidence when its
  # entire authoritative sequence was produced in order. Looking at every
  # attempt also makes direct/out-of-band outsider or duplicate rows fail
  # closed instead of letting a completed-looking prefix finish the session.
  def required_mock_completion_complete?
    return EnglishArcadeMockEvidence.qualifying?(session: @arcade_session, now: Time.current) if session_mock_id.present?

    attempts = @arcade_session.english_arcade_attempts.order(:answered_at, :id).to_a
    return false unless attempts.length == required_mock_card_keys.length
    return false unless attempts.map(&:card_key) == required_mock_card_keys

    attempts.each_with_index.all? do |attempt, index|
      expected_key = required_mock_card_keys.fetch(index)
      expected_target = EnglishArcadeCurriculum.target_for(expected_key)
      attempt.attempt_kind == "initial" &&
        attempt.target == expected_target &&
        attempt.answered_at >= @arcade_session.started_at &&
        attempt.answered_at <= (@arcade_session.finished_at || Time.current) &&
        attempt.diagnostic_evidence["answer_status"].to_s != "skip" &&
        attempt.diagnostic_evidence["outcome"].to_s != "skip" &&
        required_mock_attempt_complete?(attempt) &&
        meaningful_mock_production?(attempt) &&
        attempt.diagnostic_evidence["feynman_present"] == true &&
        attempt.feynman_text.to_s.strip.length >= MIN_TYPED_PRODUCTION_LENGTH
    end
  end

  def required_mock_attempt_complete?(attempt)
    attempt.feedback_revealed? &&
      REQUIRED_MOCK_COMPLETED_STATES.include?(attempt.state) &&
      (attempt.correct? || attempt.black_box_complete?)
  end

  def meaningful_mock_production?(attempt)
    attempt.typed_answer.to_s.strip.length >= MIN_TYPED_PRODUCTION_LENGTH &&
      attempt.diagnostic_evidence.dig("production", "typed_length").to_i >= MIN_TYPED_PRODUCTION_LENGTH
  end

  def reject_required_mock_incomplete
    respond_to do |format|
      format.html { redirect_to english_arcade_path(session_id: @arcade_session.id), alert: "Complete the current required card before starting another mock answer." }
      format.json { render json: { error: "required_mock_attempt_incomplete" }, status: :unprocessable_entity }
    end
    nil
  end

  def selectable_pack_target?(target)
    @builder.targets.key?(target) && !%w[mixed interview].include?(target)
  end

  def reject_adaptive_parent
    respond_to do |format|
      format.html { redirect_to english_arcade_path(session_id: @arcade_session.id), alert: "This adaptation needs a revealed attempt for the same card." }
      format.json { render json: { error: "compatible_revealed_parent_required" }, status: :unprocessable_entity }
    end
  end

  def reject_invalid_choice
    respond_to do |format|
      format.html { redirect_to english_arcade_path(session_id: @arcade_session.id), alert: "That answer token is invalid for this session and variant." }
      format.json { render json: { error: "invalid_answer_token" }, status: :unprocessable_entity }
    end
  end

  def reject_critical_artifact(missing)
    respond_to do |format|
      format.html { redirect_to english_arcade_path(session_id: @arcade_session.id), alert: "Complete the critical-thinking ledger before this challenge can be committed (missing: #{Array(missing).join(', ')})." }
      format.json { render json: { error: "critical_artifact_incomplete", missing: Array(missing) }, status: :unprocessable_entity }
    end
  end

  def reject_frozen_contract(attempt)
    respond_to do |format|
      format.html { redirect_to english_arcade_path(session_id: @arcade_session.id, attempt_id: attempt.id), alert: "This legacy attempt has no frozen server contract and cannot be revealed for scoring." }
      format.json { render json: { error: "frozen_contract_required", feedback_revealed: false }, status: :unprocessable_entity }
    end
  end

  def normalize_answer_status(value)
    status = value.to_s.downcase.strip
    return status if ANSWER_STATUSES.include?(status)

    "submitted"
  end

  def reject_feynman(attempt)
    respond_to do |format|
      format.html do
        redirect_to english_arcade_path(
          session_id: @arcade_session.id,
          attempt_id: attempt.id,
          card_key: attempt.card_key,
          exercise: attempt.attempt_kind,
          phase: "feynman"
        ), alert: "Add a meaningful typed Feynman explanation before feedback can be revealed."
      end
      format.json { render json: { error: "meaningful_feynman_text_required", feedback_revealed: false }, status: :unprocessable_entity }
    end
  end

  def reject_typed_production
    respond_to do |format|
      format.html { redirect_to english_arcade_path(session_id: @arcade_session.id), alert: "Write at least #{MIN_TYPED_PRODUCTION_LENGTH} characters before committing an assessable answer." }
      format.json { render json: { error: "meaningful_typed_production_required", minimum_length: MIN_TYPED_PRODUCTION_LENGTH }, status: :unprocessable_entity }
    end
  end

  class InvalidSelfRubric < StandardError; end

  def production_evidence_from(payload, typed_answer)
    scores = SELF_RUBRIC_AXES.each_with_object({}) do |axis, result|
      raw = payload["self_#{axis}"]
      next if raw.blank?

      value = Integer(raw, exception: false)
      raise InvalidSelfRubric unless value&.between?(0, 4)

      result[axis] = value
    end
    directness = payload[:english_directness].presence
    raise InvalidSelfRubric if directness.present? && !%w[english_direct mixed translated].include?(directness)

    {
      "typed_length" => typed_answer.strip.length,
      "english_directness" => directness || "not_recorded",
      "self_rubric" => scores,
      "self_assessed" => scores.any? || directness.present?,
      "assessment_scope" => "report_only"
    }
  end

  def commit_metadata_for(attempt, card, kind)
    metadata = @arcade_session.metadata.deep_stringify_keys
    metadata["active_parent_attempt_id"] = attempt.id if required_mock_card_keys.any? && kind == "initial"
    frozen_contracts = metadata["frozen_reveal_contracts"].is_a?(Hash) ? metadata["frozen_reveal_contracts"].deep_stringify_keys : {}
    frozen_contracts[attempt.id.to_s] = {
      "sources" => card.sources,
      "provenance" => card.provenance,
      "variant_id" => card.variant_id,
      "variant_digest" => card.variant_digest,
      "content_version" => card.content_version
    }
    metadata["frozen_reveal_contracts"] = frozen_contracts
    metadata
  end

  def reject_self_rubric
    respond_to do |format|
      format.html { redirect_to english_arcade_path(session_id: @arcade_session.id), alert: "Each supplied self-rubric value must be an integer from 0 to 4, with a recognised directness value." }
      format.json { render json: { error: "invalid_self_rubric", axes: SELF_RUBRIC_AXES, allowed_range: [ 0, 4 ] }, status: :unprocessable_entity }
    end
  end

  def quality_score_for(attempt, correct, feynman_text: nil)
    return 0 unless correct

    assessment = attempt.diagnostic_evidence.to_h.fetch("assessment", {}).to_h
    return 0 unless assessment["correct"] == true
    return 0 unless attempt.typed_answer.to_s.strip.length >= MIN_TYPED_PRODUCTION_LENGTH

    score = 8
    score += 1 if attempt.critical_artifact_complete?
    score += 1 if feynman_text.to_s.strip.length >= MIN_TYPED_PRODUCTION_LENGTH
    # This value is server-observable contract evidence only. Learner
    # self-ratings never enter Leitner, mastery, gate, or quality calculations.
    [ score, 10 ].min
  end

  def black_box_fields_from(payload)
    {
      "root_cause" => payload[:black_box_root_cause].to_s.truncate(4_000, omission: "…"),
      "missing_signal" => payload[:black_box_missing_signal].to_s.truncate(4_000, omission: "…"),
      "preventive_rule" => payload[:black_box_preventive_rule].to_s.truncate(4_000, omission: "…"),
      "targeted_exercise" => payload[:black_box_targeted_exercise].to_s.truncate(4_000, omission: "…"),
      "retest_dates" => payload[:black_box_retest_dates].to_s.truncate(4_000, omission: "…")
    }
  end

  def actionable_black_box_value?(value)
    text = value.to_s.strip
    return false if text.length < EnglishArcadeAttempt::BLACK_BOX_MIN_LENGTH

    !text.match?(EnglishArcadeAttempt::VAGUE_BLACK_BOX)
  end

  def reject_postmortem(attempt, missing)
    message = "Complete all five Black Box fields with actionable detail (missing: #{missing.join(', ')})."
    respond_to do |format|
      format.html do
        redirect_to english_arcade_path(
          session_id: @arcade_session.id,
          attempt_id: attempt.id,
          card_key: attempt.card_key
        ), alert: message
      end
      format.json { render json: { error: "black_box_fields_required", missing: missing }, status: :unprocessable_entity }
    end
  end

  def progress_30_days
    EnglishArcadeProgressReport.new(learner_key: learner_key).call
  end

  # The browser may export the schedule, but future interview prompts and
  # phase artifacts are revealed only when their mock is active. The HTML
  # planner keeps the richer local rendering; the JSON contract is metadata
  # only so an API consumer cannot prefetch the next challenge.
  def public_thirty_day_plan
    @thirty_day_plan.map do |day|
      copy = day.deep_dup
      copy["mocks"] = Array(copy["mocks"]).map do |mock|
        mock.slice("id", "day", "target", "mode", "duration_minutes", "required_card_keys", "breakdown", "constraints")
          .merge("phase_count" => Array(mock["phases"]).length)
      end
      copy
    end
  end

  def ratio(correct, revealed)
    return nil if revealed.to_i.zero?

    (correct.to_f / revealed.to_f).round(3)
  end

  def empty_progress_30_days
    {
      attempts: 0,
      revealed: 0,
      correct: 0,
      black_box: 0,
      targets: 0,
      target_accuracy: {},
      task_accuracy: {},
      feedback_evidence: FEEDBACK_AXES.index_with { { "observations" => 0, "attempts" => 0 } },
      capture_evidence: { "typed_count" => 0, "meaningful_typed_count" => 0, "english_directness" => {} },
      self_rubric: SELF_RUBRIC_AXES.to_h { |axis| [ axis, { "self_assessed" => true, "count" => 0, "average" => nil } ] },
      delayed_retention: { "minimum_days" => 7, "retested_after_7_days" => 0 },
      follow_up_adaptation: { "attempts" => 0 },
      baseline: {
        "status" => "pending",
        "covered_targets" => [],
        "missing_targets" => EnglishArcadeCurriculum::CANONICAL_TARGETS,
        "technical_knowledge" => {},
        "general_c2_calibrated_performance" => { "status" => "not_yet_observed" }
      },
      response_time_evidence: { "count" => 0, "average_ms" => nil, "minimum_ms" => nil, "maximum_ms" => nil },
      skill_evidence: UNASSESSED_SKILLS.index_with { { "status" => "not_assessed", "evidence_count" => 0 } },
      score_note: "Self-assessed typed practice evidence only. No CEFR certification or overall C2 result is assessed."
    }
  end

  def integer_or_nil(value)
    integer = Integer(value, exception: false)
    integer && integer.positive? ? integer : nil
  end
end
