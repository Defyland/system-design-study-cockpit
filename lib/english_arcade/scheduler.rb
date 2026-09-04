# frozen_string_literal: true

require "digest"

module EnglishArcade
  # FSRS-lite state transition functions. This module has no database or Rails
  # dependency so recorder tests can inject a clock and replay event history.
  module Scheduler
    S0 = { 1 => 0.4, 2 => 1.2, 3 => 3.0, 4 => 7.0 }.freeze
    STAGE_MULTIPLIERS = {
      "recognize" => 1.0, "trap" => 1.0, "transfer" => 1.0,
      "cloze" => 0.8, "rebuild" => 0.8, "produce" => 0.6,
      "speak" => 0.6, "feynman" => 1.5, "compress" => 1.0, "meet" => 1.0
    }.freeze
    TARGET_RETENTION = { "recognize" => 0.85, "trap" => 0.85 }.freeze

    module_function

    def retrievability(stability:, elapsed_days:)
      stability = stability.to_f
      return 0.0 if stability <= 0.0

      (1.0 + elapsed_days.to_f / (9.0 * stability))**-1
    end

    def interval_days(stability:, stage:)
      target = TARGET_RETENTION.fetch(stage.to_s, 0.90)
      9.0 * stability.to_f * (1.0 / target - 1.0)
    end

    def review(state:, rating:, stage:, reviewed_at:, attempt_no: 1, seed: nil, boss: false)
      state = stringify(state || {})
      rating = rating.to_i.clamp(1, 4)
      now = reviewed_at
      previous_stability = state.fetch("stability", 0).to_f
      previous_difficulty = state.fetch("difficulty", 5).to_f
      elapsed = elapsed_days(state["last_reviewed_at"], now)
      retrievability_before = retrievability(stability: previous_stability, elapsed_days: elapsed)
      lapses = state.fetch("lapses", 0).to_i

      if boss
        # Rain is a measurement round, not a second scheduler path. A miss is
        # due now, while a pass preserves the pending review unchanged.
        due_at = rating == 1 ? now : (state["due_at"] || now + interval_days(stability: previous_stability, stage: stage) * 86_400)
        return transition(
          stability: previous_stability, difficulty: previous_difficulty,
          status: state.fetch("status", "review"), lapses: lapses,
          retrievability: retrievability_before, interval: 0.0, now: now, due_at: due_at,
          last_result: rating == 1 ? "boss_miss" : "boss_pass"
        )
      end

      if rating == 1
        stability = [ [ previous_stability * 0.3, 0.4 ].max, 3.0 ].min
        return transition(
          stability: stability, difficulty: previous_difficulty, status: "relearning", lapses: lapses + 1,
          retrievability: retrievability_before, interval: 0.0, now: now, due_at: now
        )
      end

      if previous_stability <= 0.0
        stability = S0.fetch(rating) * STAGE_MULTIPLIERS.fetch(stage.to_s, 1.0)
        difficulty = clamp(5.0 + 1.5 * (3 - rating), 1.0, 10.0)
      elsif attempt_no.to_i > 1
        # An in-lesson relearn only proves recovery from the immediate miss.
        stability = previous_stability
        difficulty = previous_difficulty
      else
        growth = Math.exp(1.5) * (11.0 - previous_difficulty) * (previous_stability**-0.2) * (Math.exp(1.0 - retrievability_before) - 1.0)
        growth *= 0.8 if rating == 2
        growth *= 1.3 if rating == 4
        stability = [ previous_stability * (1.0 + growth), previous_stability * 1.05 ].max
        difficulty = 0.95 * clamp(previous_difficulty + 0.7 * (3 - rating), 1.0, 10.0) + 0.25
      end
      scheduled = interval_days(stability: stability, stage: stage)
      fuzzed = scheduled * fuzz(seed || default_seed(state, stage, now))
      transition(
        stability: stability, difficulty: difficulty, status: "review", lapses: lapses,
        retrievability: retrievability_before, interval: fuzzed, now: now, due_at: now + fuzzed * 86_400
      )
    end

    def fuzz(seed)
      value = Digest::SHA256.hexdigest(seed.to_s)[0, 16].to_i(16).fdiv(0xffff_ffff_ffff_ffff)
      0.95 + value * 0.10
    end

    def clamp(value, minimum, maximum)
      [ [ value, minimum ].max, maximum ].min
    end

    def transition(stability:, difficulty:, status:, lapses:, retrievability:, interval:, now:, due_at:, last_result: nil)
      {
        "stability" => stability,
        "difficulty" => difficulty,
        "status" => status,
        "lapses" => lapses,
        "last_result" => last_result || (status == "relearning" ? "lapse" : "success"),
        "last_reviewed_at" => now,
        "due_at" => due_at,
        "retrievability" => retrievability,
        "scheduled_interval_days" => interval
      }
    end
    private_class_method :transition

    def elapsed_days(previous, now)
      return 0.0 unless previous && now

      [ (now.to_f - previous.to_f) / 86_400.0, 0.0 ].max
    end
    private_class_method :elapsed_days

    def default_seed(state, stage, now)
      [ state["card_key"], stage, state["reps"], now.to_i ].join("\u0000")
    end
    private_class_method :default_seed

    def stringify(value)
      value.each_with_object({}) { |(key, nested), result| result[key.to_s] = nested } if value.is_a?(Hash)
    end
    private_class_method :stringify
  end
end
