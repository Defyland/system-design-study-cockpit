class EnglishArcadeController < ApplicationController
  ANSWER_STATUSES = %w[submitted correct wrong partial reveal skip].freeze
  RESET_STATUSES = %w[wrong partial reveal skip].freeze
  FEEDBACK_AXES = %w[register hedging precision grammar pragmatics].freeze
  UNASSESSED_SKILLS = %w[listening pronunciation spontaneous_fluency].freeze

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
      requested = requested_card
      revealed_initial = @feedback_attempt && normalize_attempt_kind(params[:exercise]) == "initial"
      @current_card = revealed_initial ? @plan.cards.first : (requested || @plan.cards.first)
      @feedback_card = requested_attempt && @builder.card_for(
        target: @arcade_session.target,
        card_key: requested_attempt.card_key
      )
      @feedback = @feedback_attempt&.diagnostic_evidence&.fetch("feedback", nil)
      @exercise = normalize_attempt_kind(params[:exercise])
    end

    respond_to do |format|
      format.html
      format.json do
        render json: {
          session_id: @arcade_session&.id,
          target: @selected_target,
          mode: @selected_mode,
          cards: @plan ? @plan.cards.map { |card| @builder.prompt_snapshot(card) } : [],
          feedback_revealed: @feedback_attempt&.feedback_revealed? || false,
          feedback: (@feedback_attempt&.feedback_revealed? ? @feedback : nil),
          schedule: @schedule_summary,
          progress_30_days: @progress_30_days,
          thirty_day_plan: @thirty_day_plan
        }
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
    target = @builder.normalize_target(payload[:target].presence || params.dig(:english_arcade_session, :target) || params[:target])
    mode = @builder.normalize_mode(payload[:mode].presence || params.dig(:english_arcade_session, :mode) || params[:mode])
    now = Time.current
    duration = @builder.modes.fetch(mode).fetch(:duration_seconds)

    @arcade_session = EnglishArcadeSession.create!(
      learner_key: learner_key,
      target: target,
      mode: mode,
      duration_seconds: duration,
      started_at: now,
      expires_at: now + duration.seconds,
      metadata: {
        "source" => "english_arcade_launcher",
        "content_source" => @builder.call(target: target, mode: mode, learner_key: learner_key, limit: 1).source,
        "target_key" => target,
        "mode" => mode
      }
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

    if @arcade_session.expired?(at: Time.current) && !pending_attempt
      @arcade_session.expire!
      return redirect_to english_arcade_path(session_id: @arcade_session.id), alert: "This timed session has ended."
    end

    @builder = EnglishArcadeSessionBuilder.new

    return finalize_attempt(pending_attempt, payload) if payload[:phase].to_s == "feynman" && pending_attempt
    return save_postmortem(pending_attempt, payload) if payload[:phase].to_s == "postmortem" && pending_attempt

    commit_attempt(payload)
  rescue ActiveRecord::RecordInvalid => error
    redirect_to english_arcade_path(session_id: @arcade_session.id), alert: error.record.errors.full_messages.to_sentence
  end

  def commit_attempt(payload)
    card = @builder.card_for(target: @arcade_session.target, card_key: payload[:card_key])
    return redirect_to english_arcade_path(session_id: @arcade_session.id), alert: "That question is no longer available." unless card

    kind = normalize_attempt_kind(payload[:attempt_kind])
    requested_status = payload[:answer_status].presence || payload[:outcome].presence
    requested_status ||= payload[:phase] if RESET_STATUSES.include?(payload[:phase].to_s)
    requested_status = "skip" if payload[:skip].to_s == "1"
    answer_status = normalize_answer_status(requested_status)
    typed_answer = payload[:typed_answer].to_s.truncate(4_000, omission: "…")
    spoken_text = payload[:spoken_text].to_s.truncate(4_000, omission: "…")
    if RESET_STATUSES.include?(answer_status) && payload[:answer_choice].blank? && typed_answer.blank? && spoken_text.blank?
      typed_answer = "[#{answer_status}]"
    end
    grade = @builder.grade(
      card: card,
      answer_choice: payload[:answer_choice],
      typed_answer: typed_answer,
      spoken_text: spoken_text
    )
    parent_attempt = @arcade_session.english_arcade_attempts.find_by(id: payload[:parent_attempt_id])
    now = Time.current

    attempt = nil
    EnglishArcadeSession.transaction do
      schedule = @builder.schedule_for(card: card, learner_key: learner_key, on: now.to_date)
      schedule.with_lock do
        box_before = schedule.box
        diagnostic = grade.diagnostic_evidence.merge(
          "attempt_kind" => kind,
          "response_ms" => integer_or_nil(payload[:response_ms]),
          "state" => "feynman",
          "answer_status" => answer_status,
          "outcome" => answer_status
        )
        attempt = @arcade_session.english_arcade_attempts.create!(
          learner_key: learner_key,
          target: card.target,
          card_key: card.key,
          attempt_kind: kind,
          parent_attempt: parent_attempt,
          answer_choice: payload[:answer_choice].to_s.strip.presence,
          typed_answer: typed_answer.presence,
          spoken_text: spoken_text.presence,
          correct: grade.correct,
          feedback_revealed: false,
          state: "feynman",
          variant_key: kind,
          quality_score: grade.correct && !RESET_STATUSES.include?(answer_status) ? 8 : 0,
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
        score: @arcade_session.score
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
          box_before: attempt.box_before
        }, status: :created
      end
    end
  end

  def finalize_attempt(pending_attempt, payload)
    return redirect_to english_arcade_path(session_id: @arcade_session.id), alert: "That attempt is already revealed." if pending_attempt.feedback_revealed?

    card = @builder.card_for(target: @arcade_session.target, card_key: pending_attempt.card_key)
    return redirect_to english_arcade_path(session_id: @arcade_session.id), alert: "That question is no longer available." unless card

    feynman_text = payload[:feynman_text].to_s.truncate(4_000, omission: "…")
    return reject_feynman(pending_attempt) if feynman_text.blank?

    spoken_text = pending_attempt.spoken_text.to_s
    grade = @builder.grade(
      card: card,
      answer_choice: pending_attempt.answer_choice,
      typed_answer: pending_attempt.typed_answer,
      spoken_text: spoken_text
    )
    answer_status = normalize_answer_status(pending_attempt.diagnostic_evidence["answer_status"] || pending_attempt.diagnostic_evidence["outcome"])
    effective_correct = grade.correct && !RESET_STATUSES.include?(answer_status)
    now = Time.current
    EnglishArcadeSession.transaction do
      schedule = @builder.schedule_for(card: card, learner_key: learner_key, on: now.to_date)
      schedule.with_lock do
        schedule.record!(correct: true, at: now) if effective_correct
        # A wrong reveal persists at feedback until the required Black Box
        # reflection is submitted; only then does it become scheduled.
        state = effective_correct ? "scheduled" : "feedback"
        diagnostic = pending_attempt.diagnostic_evidence.merge(
          "feedback" => grade.feedback,
          "feynman_present" => true,
          "state" => state,
          "black_box_required" => !effective_correct
        )
        pending_attempt.update!(
          state: state,
          feedback_revealed: true,
          correct: effective_correct,
          quality_score: effective_correct ? 10 : 0,
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
          card_key: card.key,
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
          next_interval: effective_correct ? EnglishArcadeCard.find_by(learner_key: learner_key, target: card.target, card_key: card.key)&.interval_label : nil,
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

  def finish
    return redirect_to english_arcade_path unless @arcade_session

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

  def session_payload
    source = params[:english_arcade_session]
    source.respond_to?(:permit) ? source.permit(:target, :mode) : params.permit(:target, :mode)
  end

  def attempt_payload
    params.fetch(:english_arcade_attempt, params).permit(
      :card_key, :attempt_kind, :answer_choice, :typed_answer, :spoken_text,
      :response_ms, :parent_attempt_id, :attempt_id, :phase, :feynman_text,
      :answer_status, :outcome, :postmortem_text, :black_box_root_cause,
      :black_box_missing_signal, :black_box_preventive_rule,
      :black_box_targeted_exercise, :black_box_retest_dates,
      :black_box_symptom, :black_box_expected, :black_box_actual, :black_box_repair,
      :skip
    )
  end

  def persist_launcher_choice(target, mode)
    cockpit_session[:english_arcade_target] = target
    cockpit_session[:english_arcade_mode] = mode
  end

  def requested_card
    return unless params[:card_key].present?

    @builder.card_for(target: @arcade_session.target, card_key: params[:card_key])
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
        ), alert: "Add a Feynman explanation before feedback can be revealed."
      end
      format.json { render json: { error: "feynman_text_required", feedback_revealed: false }, status: :unprocessable_entity }
    end
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
    since = 30.days.ago
    attempts = EnglishArcadeAttempt.where(learner_key: learner_key).where("answered_at >= ?", since)
    revealed_attempts = attempts.where(feedback_revealed: true).to_a
    target_accuracy = Hash.new { |hash, key| hash[key] = { "attempts" => 0, "revealed" => 0, "correct" => 0, "accuracy" => nil } }
    task_accuracy = Hash.new { |hash, key| hash[key] = { "target" => nil, "attempts" => 0, "revealed" => 0, "correct" => 0, "accuracy" => nil } }
    feedback_evidence = FEEDBACK_AXES.index_with { |axis| { "observations" => 0, "attempts" => 0 } }
    skill_evidence = UNASSESSED_SKILLS.index_with { |skill| { "status" => "not_assessed", "evidence_count" => 0 } }

    attempts.find_each do |attempt|
      target = target_accuracy[attempt.target]
      target["attempts"] += 1
      task_key = "#{attempt.target}:#{attempt.card_key}"
      task = task_accuracy[task_key]
      task["target"] = attempt.target
      task["attempts"] += 1
      next unless attempt.feedback_revealed?

      target["revealed"] += 1
      task["revealed"] += 1
      if attempt.correct?
        target["correct"] += 1
        task["correct"] += 1
      end

      feedback = attempt.diagnostic_evidence.fetch("feedback", {})
      FEEDBACK_AXES.each do |axis|
        next unless feedback[axis].to_s.strip.present?

        feedback_evidence[axis]["observations"] += 1
        feedback_evidence[axis]["attempts"] += 1
      end

      actual_skills = attempt.diagnostic_evidence.fetch("skill_evidence", {})
      UNASSESSED_SKILLS.each do |skill|
        next unless actual_skills[skill].present?

        skill_evidence[skill] = {
          "status" => "observed",
          "evidence_count" => skill_evidence.fetch(skill).fetch("evidence_count") + 1
        }
      end
    end

    target_accuracy.each_value { |entry| entry["accuracy"] = ratio(entry["correct"], entry["revealed"]) }
    task_accuracy.each_value { |entry| entry["accuracy"] = ratio(entry["correct"], entry["revealed"]) }
    response_times = attempts.where.not(response_ms: nil).pluck(:response_ms).filter(&:positive?)
    typed_count = attempts.where.not(typed_answer: nil).count
    spoken_count = attempts.where.not(spoken_text: nil).count

    {
      attempts: attempts.count,
      revealed: revealed_attempts.length,
      correct: revealed_attempts.count(&:correct?),
      black_box: attempts.where("diagnostic_evidence ->> 'black_box_required' = ?", "true").count,
      targets: revealed_attempts.map(&:target).uniq.length,
      target_accuracy: target_accuracy,
      task_accuracy: task_accuracy,
      feedback_evidence: feedback_evidence,
      capture_evidence: {
        "typed_count" => typed_count,
        "spoken_count" => spoken_count
      },
      response_time_evidence: {
        "count" => response_times.length,
        "average_ms" => response_times.any? ? (response_times.sum.to_f / response_times.length).round : nil,
        "minimum_ms" => response_times.min,
        "maximum_ms" => response_times.max
      },
      skill_evidence: skill_evidence,
      score_note: "Practice evidence only; no CEFR score is assessed."
    }
  rescue ActiveRecord::StatementInvalid
    empty_progress_30_days
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
      capture_evidence: { "typed_count" => 0, "spoken_count" => 0 },
      response_time_evidence: { "count" => 0, "average_ms" => nil, "minimum_ms" => nil, "maximum_ms" => nil },
      skill_evidence: UNASSESSED_SKILLS.index_with { { "status" => "not_assessed", "evidence_count" => 0 } },
      score_note: "Practice evidence only; no CEFR score is assessed."
    }
  end

  def integer_or_nil(value)
    integer = Integer(value, exception: false)
    integer && integer.positive? ? integer : nil
  end
end
