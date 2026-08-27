# frozen_string_literal: true

# Canonical contract for English C2 Arcade interview content.
#
# This file is plain Ruby on purpose: it must be loadable without booting
# Rails so the pack validator can run as a fast standalone command.
module EnglishArcade
  module Schema
    CONTRACT_VERSION = "1.4.0"
    TRANSITION_CONTRACT_VERSION = "1.5.0"
    RESPONSE_VERSIONS_CONTRACT_VERSION = "1.6.0"
    SUPPORTED_CONTRACT_VERSIONS = %w[1.1.0 1.2.0 1.3.0 1.4.0 1.5.0 1.6.0].freeze
    CANONICAL_CONTRACT_VERSIONS = [ CONTRACT_VERSION, TRANSITION_CONTRACT_VERSION, RESPONSE_VERSIONS_CONTRACT_VERSION ].freeze
    RESPONSE_VERSIONS_ALLOWED_CONTRACT_VERSIONS = %w[1.4.0 1.5.0 1.6.0].freeze

    # Selectable practice targets. Order is the canonical launcher order.
    TARGETS = %w[
      dsa
      ruby
      rails
      react
      golang
      elixir
      databases
      general
      career
      rails_experience
      go_experience
      elixir_experience
      system_design
      salesforce
    ].freeze

    # Salesforce remains selectable but is explicitly outside the required
    # eight technical tracks plus general professional conversation.
    CANONICAL_TARGETS = %w[
      dsa ruby rails react golang elixir databases general
      career rails_experience go_experience elixir_experience system_design
    ].freeze
    # Every required interview pack uses the same learner loop.  Salesforce is
    # elective and remains outside this stricter authored-coaching contract.
    CANONICAL_INTERVIEW_CONTENT_TARGETS = CANONICAL_TARGETS.freeze
    ELECTIVE_TARGETS = %w[salesforce].freeze

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
    # is simply the longest one. The ratio is measured in normalized words;
    # the cap keeps very long answers from requiring impractically long options.
    BEST_ANSWER_TO_DISTRACTOR_WORD_RATIO = 1.6
    MAX_DISTRACTOR_WORDS_FOR_LENGTH_TELL = 50

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

    # Evidence-oriented packs deliberately carry provenance next to the
    # learner-facing source list. That record is kept machine-readable so an
    # interview answer cannot silently overstate a portfolio or resume claim.
    PROVENANCE_REQUIRED_TARGETS = %w[career rails_experience go_experience elixir_experience].freeze
    EVIDENCE_CLASSES = %w[
      resume_derived deployed_personal_project portfolio_code public_challenge
    ].freeze
    CONFIDENTIALITY_RISK_LEVELS = %w[low medium high].freeze
    REQUIRED_PROVENANCE_KEYS = %w[
      evidence_class project repository files verified_claims
      confirmation_required safe_interview_version confidentiality
    ].freeze
    REQUIRED_PROVENANCE_FILE_KEYS = %w[path commit claim].freeze
    REQUIRED_CONFIDENTIALITY_KEYS = %w[level note].freeze

    OPTIONAL_ITEM_KEYS = %w[template pt_help follow_up compression extension provenance critical_thinking response_versions].freeze

    REQUIRED_DISTRACTOR_KEYS = %w[text trap why_wrong].freeze
    REQUIRED_REPHRASE_KEYS = %w[prompt goal].freeze
    REQUIRED_RECALL_KEYS = %w[
      active_recall_cue
      leitner_start_box
      mastery_threshold
    ].freeze
    REQUIRED_CANONICAL_RECALL_KEYS = %w[
      active_recall_cue
      feynman_prompt
      black_box_probe
      leitner_start_box
      mastery_threshold
      delayed_variant
    ].freeze

    # Feynman explanation contract. The keys are fixed so the session engine can
    # render the same four prompts for every item without per-item branching.
    REQUIRED_FEYNMAN_KEYS = %w[concept explain_to constraint self_check].freeze
    REQUIRED_CANONICAL_FEYNMAN_KEYS = %w[concept explain_to constraint self_check reasoning_check].freeze

    # Black Box post-mortem, run only after an error. Five fields, in order:
    # what you saw, what was expected, what you produced, why, and the repair.
    REQUIRED_BLACK_BOX_KEYS = %w[symptom expected actual root_cause repair].freeze
    REQUIRED_CANONICAL_BLACK_BOX_KEYS = %w[symptom expected actual root_cause repair reasoning_error].freeze

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
      "follow_up_prompt" => 40,
      "compression_prompt" => 40,
      "recall_text" => 15,
      "feynman_text" => 15,
      "black_box_text" => 15,
      "card_text" => 15,
      "source_note" => 10
    }.freeze

    CRITICAL_THINKING_RUBRIC_AXES = %w[
      facts_correct
      assumptions_explicit
      alternatives_considered
      tradeoff_quality
      follow_up_adaptation
      certainty_calibration
    ].freeze
    CRITICAL_THINKING_FAILURE_KINDS = %w[counterexample edge_case failure_mode].freeze
    CRITICAL_THINKING_CHALLENGE_KINDS = %w[assumption evidence alternative failure new_evidence].freeze
    CRITICAL_THINKING_SOURCE_KINDS = %w[
      primary_code official_documentation research_consensus secondary user_material
      authored_scenario resume_derived
    ].freeze
    CRITICAL_THINKING_CERTAINTY_LEVELS = %w[high medium low].freeze
    REQUIRED_TARGET_CRITICAL_THINKING_KEYS = %w[learner_prompts rubric].freeze
    REQUIRED_TARGET_CRITICAL_THINKING_PROMPTS = %w[
      evidence_ledger problem_frame comparison failure_probe certainty_review
    ].freeze
    REQUIRED_ITEM_CRITICAL_THINKING_KEYS = %w[
      problem_frame claim_map comparison failure_probe evidence_check certainty rubric
    ].freeze
    REQUIRED_CLAIM_MAP_KEYS = %w[fact inference assumption unknown].freeze
    REQUIRED_COMPARISON_TRUE_KEYS = %w[applicable alternatives decision_rule].freeze
    REQUIRED_COMPARISON_FALSE_KEYS = %w[applicable rejected_alternative hard_constraint decision_rule].freeze
    REQUIRED_ALTERNATIVE_KEYS = %w[option benefit cost_or_risk valid_when].freeze
    REQUIRED_FAILURE_PROBE_KEYS = %w[kind prompt].freeze
    REQUIRED_EVIDENCE_CHECK_KEYS = %w[basis source_kind limitation checked_on].freeze
    REQUIRED_CERTAINTY_KEYS = %w[level rationale update_trigger].freeze
    REQUIRED_FOLLOW_UP_KEYS = %w[prompt goal challenge_kind best_answer distractors].freeze
    OPTIONAL_FOLLOW_UP_KEYS = %w[answer_anchors].freeze
    REQUIRED_TRANSITION_FOLLOW_UP_KEYS = (REQUIRED_FOLLOW_UP_KEYS + OPTIONAL_FOLLOW_UP_KEYS).freeze
    REQUIRED_ADAPTIVE_DISTRACTOR_KEYS = %w[text why_wrong].freeze
    REQUIRED_EXTENSION_KEYS = %w[prompt goal].freeze
    REQUIRED_DELAYED_VARIANT_KEYS = %w[id prompt changed_constraint new_evidence best_answer distractors].freeze
    OPTIONAL_DELAYED_VARIANT_KEYS = %w[answer_anchors reasoning_moves].freeze
    REQUIRED_TRANSITION_DELAYED_VARIANT_KEYS = (REQUIRED_DELAYED_VARIANT_KEYS + OPTIONAL_DELAYED_VARIANT_KEYS).freeze
    REASONING_MOVE_KEYS = %w[preserve revise verify certainty_update].freeze
    REASONING_MOVE_MIN_LENGTH = 20
    REQUIRED_DELAYED_DISTRACTOR_KEYS = %w[text why_wrong].freeze
    REQUIRED_CARD_CRITICAL_THINKING_KEYS = %w[cue check].freeze
    OPTIONAL_ITEM_CRITICAL_THINKING_KEYS = %w[defense_checks].freeze
    REQUIRED_TRANSITION_ITEM_CRITICAL_THINKING_KEYS = (REQUIRED_ITEM_CRITICAL_THINKING_KEYS + OPTIONAL_ITEM_CRITICAL_THINKING_KEYS).freeze
    DEFENSE_CHECK_KEYS = %w[id axis prompt best_answer distractors].freeze
    DEFENSE_CHECK_AXES = %w[facts assumptions alternatives tradeoff adaptation certainty].freeze
    ANSWER_ANCHOR_MIN_LENGTH = 12
    ANSWER_ANCHOR_MAX_LENGTH = 180
    REQUIRED_RESPONSE_VERSION_KEYS = %w[short medium deep].freeze
    RESPONSE_VERSION_WORD_RANGES = {
      "short" => (20..70),
      "medium" => (50..140),
      "deep" => (100..260)
    }.freeze

    # Repositories an item may attribute a source to.
    SOURCE_REPOS = %w[backend-challenges system-design-estudos system-design-study-cockpit original].freeze

    def self.target?(value)
      TARGETS.include?(value)
    end

    def self.template_required?(target)
      TEMPLATE_REQUIRED_TARGETS.include?(target)
    end

    def self.provenance_required?(target)
      PROVENANCE_REQUIRED_TARGETS.include?(target)
    end

    def self.leitner_interval_days(box)
      LEITNER_INTERVAL_DAYS.fetch(box)
    end
  end
end
