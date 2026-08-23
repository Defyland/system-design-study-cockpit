# frozen_string_literal: true

# Canonical contract for English C2 Arcade interview content.
#
# This file is plain Ruby on purpose: it must be loadable without booting
# Rails so the pack validator can run as a fast standalone command.
module EnglishArcade
  module Schema
    CONTRACT_VERSION = "1.1.0"

    # Selectable practice targets. Order is the canonical launcher order.
    TARGETS = %w[
      dsa
      ruby
      rails
      react
      golang
      elixir
      salesforce
      system_design
    ].freeze

    # Targets whose answers are only credible when they follow a delivery
    # template, so the learner practises structure and language together.
    TEMPLATE_REQUIRED_TARGETS = %w[dsa system_design].freeze

    # Where an item sits in a real hiring loop. Drives session pacing.
    INTERVIEW_STAGES = %w[
      recruiter_screen
      technical_screen
      live_coding
      deep_dive
      architecture_review
      behavioural_probe
    ].freeze

    # The language failure a distractor is designed to expose. These are the
    # same five axes every item must give feedback on.
    LANGUAGE_AXES = %w[register hedging precision grammar pragmatics].freeze

    DIFFICULTIES = (1..3).freeze
    LEITNER_BOXES = (1..5).freeze

    # Leitner intervals in days: daily / 2d / 4d / weekly / 2-weekly.
    LEITNER_INTERVAL_DAYS = { 1 => 1, 2 => 2, 3 => 4, 4 => 7, 5 => 14 }.freeze

    # Mastery: >= 8/10 on two attempts separated by about a week.
    MASTERY_SCORE = 8
    MASTERY_SCALE = 10
    MASTERY_ATTEMPTS = 2
    MASTERY_SPACING_DAYS = 7

    # 8 is the hard contractual floor; 12 is the publishable bar every target
    # must clear before release. Both are enforced, with different severities.
    MINIMUM_ITEMS_PER_TARGET = 8
    PUBLISHABLE_ITEMS_PER_TARGET = 12
    MINIMUM_DISTRACTORS = 2

    # Production Leitner cards distilled from the pack. Fewer than two is not a
    # deck; more than five stops being the distilled core.
    MINIMUM_CARDS_PER_TARGET = 2
    MAXIMUM_CARDS_PER_TARGET = 5

    # Guard against the classic multiple-choice tell where the correct option
    # is simply the longest one. Kept as a ratio so packs stay editable.
    MAX_BEST_ANSWER_LENGTH_RATIO = 1.6

    REQUIRED_ITEM_KEYS = %w[
      id
      version
      target
      topic
      difficulty
      interview_stage
      prompt
      context
      best_answer
      distractors
      feedback
      rephrase
      language_focus
      feynman
      black_box
      recall
      sources
    ].freeze

    OPTIONAL_ITEM_KEYS = %w[template pt_help].freeze

    REQUIRED_DISTRACTOR_KEYS = %w[text trap why_wrong].freeze
    REQUIRED_REPHRASE_KEYS = %w[prompt goal].freeze
    REQUIRED_RECALL_KEYS = %w[
      active_recall_cue
      leitner_start_box
      mastery_threshold
    ].freeze

    # Feynman explanation contract. The keys are fixed so the session engine can
    # render the same four prompts for every item without per-item branching.
    REQUIRED_FEYNMAN_KEYS = %w[concept explain_to constraint self_check].freeze

    # Black Box post-mortem, run only after an error. Five fields, in order:
    # what you saw, what was expected, what you produced, why, and the repair.
    REQUIRED_BLACK_BOX_KEYS = %w[symptom expected actual root_cause repair].freeze

    REQUIRED_CARD_KEYS = %w[id front back box source].freeze
    REQUIRED_SOURCE_KEYS = %w[repo path note].freeze

    REQUIRED_TARGET_KEYS = %w[key label blurb focus_areas simulation].freeze
    REQUIRED_TEMPLATE_KEYS = %w[id label applies_to steps source].freeze

    # Semantic-ish item version. Content edits that change meaning must bump it.
    ITEM_VERSION_FORMAT = /\A\d+\.\d+\.\d+\z/

    # Minimum useful lengths. Short enough to stay authorable, long enough to
    # reject placeholder content.
    MIN_LENGTHS = {
      "prompt" => 40,
      "context" => 40,
      "best_answer" => 80,
      "distractor_text" => 20,
      "why_wrong" => 20,
      "feedback" => 20,
      "rephrase_prompt" => 20,
      "rephrase_goal" => 15,
      "recall_text" => 15,
      "feynman_text" => 15,
      "black_box_text" => 15,
      "card_text" => 15,
      "source_note" => 10
    }.freeze

    # Repositories an item may attribute a source to.
    SOURCE_REPOS = %w[system-design-estudos system-design-study-cockpit original].freeze

    def self.target?(value)
      TARGETS.include?(value)
    end

    def self.template_required?(target)
      TEMPLATE_REQUIRED_TARGETS.include?(target)
    end

    def self.leitner_interval_days(box)
      LEITNER_INTERVAL_DAYS.fetch(box)
    end
  end
end
