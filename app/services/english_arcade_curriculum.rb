# frozen_string_literal: true

require "time"
require_relative "../../lib/english_arcade/schema"

# The server-side curriculum is the source of truth for what the 30-day
# launcher schedules. Packs remain content-owned; this record only schedules
# their stable item ids and the timed mock sequences that exercise them.
class EnglishArcadeCurriculum
  TECHNICAL_TARGETS = %w[dsa ruby rails react golang elixir databases system_design].freeze
  CANONICAL_TARGETS = EnglishArcade::Schema::CANONICAL_TARGETS.freeze
  EXPERIENCE_TARGETS = %w[career rails_experience go_experience elixir_experience].freeze

  BASELINE_ITEM_IDS = [
    "general-01-introduction",
    "dsa-01-pattern-naming",
    "ruby-01-blocks-vs-procs",
    "rails-01-n-plus-one",
    "react-01-state-ownership",
    "career-01-a-60-to-90-second-introduction",
    "rails_experience-01-early-rails-integrations-and-geospatial-work",
    "golang-01-interface-placement",
    "elixir-01-process-model",
    "databases-01-modeling-constraints",
    "go_experience-01-backend-service-template-memory-idempotency",
    "elixir_experience-01-pulseops-transactional-enqueue",
    "system_design-01-requirements-first"
  ].freeze

  EXPERIENCE_ITEM_IDS = {
    "career" => %w[
      career-01-a-60-to-90-second-introduction
      career-02-a-recruiter-introduction
      career-03-an-engineering-introduction
      career-04-a-chronological-walkthrough
      career-05-short-medium-and-deep-compression
      career-06-role-fit-and-why-now
      career-07-recruiter-engineer-staff-stakeholder-adaptation
      career-08-star-and-care-framing
      career-09-a-difficult-metric-follow-up
      career-10-clarification-before-commitment
      career-11-confidentiality-safe-handling
      career-12-what-i-would-change-now
    ],
    "rails_experience" => %w[
      rails_experience-01-early-rails-integrations-and-geospatial-work
      rails_experience-02-a-growing-ecommerce-api
      rails_experience-03-payment-performance-and-safe-rollout
      rails_experience-04-application-security-and-idor
      rails_experience-05-recent-volume-finance-and-messaging
      rails_experience-06-job-search-dashboard-retries-and-throttling
      rails_experience-07-study-cockpit-committed-release-evidence
      rails_experience-08-settleflow-idempotency-and-locks
      rails_experience-09-flowbridge-recovery-and-ssrf
      rails_experience-10-rediscraft-reactor-and-aof
      rails_experience-11-ractorized-rails-research-boundary
      rails_experience-12-activerecord-optimizer-validation
      rails_experience-13-supportnest-deterministic-routing-experiments
      rails_experience-14-fiscalbridge-provider-boundary
      rails_experience-15-openbank-simulation-boundary
      rails_experience-16-ticketboard-clean-architecture-tradeoff
      rails_experience-17-railsdoctor-context-and-redaction-boundary
      rails_experience-18-solidlens-explain-hypothesis-boundary
      rails_experience-19-rinha-rails-versus-ruby-knn-study
      rails_experience-20-local-review-tooling-pipeline-boundaries
    ],
    "go_experience" => %w[
      go_experience-01-backend-service-template-memory-idempotency
      go_experience-02-bankport-concurrent-idempotency-middleware
      go_experience-03-fulfillhub-local-transaction-and-outbox-delivery
      go_experience-04-gocachelab-aof-durability-and-recovery
      go_experience-05-kubepulse-policy-and-level-triggered-reconciliation
      go_experience-06-pixguard-atomic-screening-and-outbox-leases
      go_experience-07-pixrail-claim-before-spi-side-effect
      go_experience-08-rinha-go-exact-knn-scaling-boundary
      go_experience-09-terraport-lifecycle-import-and-ambiguous-retry
      go_experience-10-tokenforge-deterministic-byte-bpe-boundary
      go_experience-11-tracebridge-bounded-admission-and-retry-stall
      go_experience-12-trustvault-secret-lifecycle-and-ssrf-boundary
    ],
    "elixir_experience" => %w[
      elixir_experience-01-pulseops-transactional-enqueue
      elixir_experience-02-pulseops-per-tenant-queue-limit
      elixir_experience-03-pulseops-terminal-reconciliation
      elixir_experience-04-reportforge-inflight-cancellation
      elixir_experience-05-reportforge-staged-artifact-compensation
      elixir_experience-06-reportforge-stream-first-boundary
      elixir_experience-07-reconpulse-atomic-replay-request
      elixir_experience-08-reconpulse-webhook-failure-circuit-risk
      elixir_experience-09-reconpulse-broker-and-ssrf-boundaries
      elixir_experience-10-rinha-elixir-supervised-resource-reload
      elixir_experience-11-rinha-elixir-exact-knn-scaling-baseline
      elixir_experience-12-rinha-elixir-genserver-serialization-risk
    ]
  }.freeze

  # Kept as a compatibility name for callers from the first curriculum
  # release. It is not a qualifying mock anymore; only a spec with `mock_id`
  # can satisfy a gate.
  GENERAL_FINAL_MOCK_ITEM_IDS = %w[
    general-06-star-conflict
    general-09-incident-update
    general-12-interview-close
  ].freeze

  DSA_BREAKDOWN = [
    [ "clarify and state invariant", 5 ],
    [ "choose pattern and approach", 8 ],
    [ "code and test edge cases", 20 ],
    [ "defend complexity and follow-up", 8 ],
    [ "Feynman and Black Box", 4 ]
  ].freeze
  SYSTEM_DESIGN_BREAKDOWN = [
    [ "clarify requirements", 5 ],
    [ "SLOs and constraints", 5 ],
    [ "capacity estimates", 8 ],
    [ "high-level design", 10 ],
    [ "deep dive on data and API", 10 ],
    [ "failures and trade-offs", 5 ],
    [ "summary and next step", 2 ]
  ].freeze
  DSA_PHASES = [
    {
      "id" => "clarify_contract",
      "label" => "Clarify the coding contract",
      "minutes" => 5,
      "brief" => "Clarify the input/output contract, constraints, invalid or empty input behavior, and expected complexity before writing code.",
      "artifact_prompt" => "Write the input/output contract, constraints, two concrete examples, and one edge case. Do not write implementation code yet.",
      "minimum_chars" => 40
    },
    {
      "id" => "choose_approach",
      "label" => "Choose the pattern and invariant",
      "minutes" => 8,
      "brief" => "Compare at least two approaches. Choose one, state the invariant that makes it correct, and outline the pointer or state movement.",
      "artifact_prompt" => "Submit pseudocode, the loop invariant or state condition, and a provisional time/space bound. Explain why the chosen progress measure does not move backward unnecessarily.",
      "minimum_chars" => 40
    },
    {
      "id" => "code_and_test",
      "label" => "Code and test edge cases",
      "minutes" => 20,
      "brief" => "Implement the chosen solution. The interviewer expects readable code and tests that expose a boundary case, a repeated-value case, and a normal case.",
      "artifact_prompt" => "Paste a runnable method or function and at least three focused tests, including one invalid-boundary case, one adversarial repeated or tied case, and one normal case.",
      "minimum_chars" => 80
    },
    {
      "id" => "defend_complexity",
      "label" => "Defend complexity and follow-up",
      "minutes" => 8,
      "brief" => "Defend the cost of your implementation by accounting for each major operation. Then answer one changed-constraint or scaling follow-up.",
      "artifact_prompt" => "Write a short complexity proof, identify the memory bound, and answer one scaling follow-up with a concrete trade-off.",
      "minimum_chars" => 40
    },
    {
      "id" => "feynman_black_box",
      "label" => "Feynman and Black Box",
      "minutes" => 4,
      "brief" => "Teach the algorithmic decision to a teammate who can read code but has not seen this invariant. Name one plausible bug and the signal that would expose it.",
      "artifact_prompt" => "Explain the invariant or state condition in plain language, give one trace, and write a Black Box repair rule for the bug you would test first.",
      "minimum_chars" => 40
    }
  ].freeze
  SYSTEM_DESIGN_PHASES = [
    {
      "id" => "clarify_requirements",
      "label" => "Clarify requirements",
      "minutes" => 5,
      "brief" => "Start by separating the user-visible success criteria from scope that the interviewer has not granted.",
      "artifact_prompt" => "Write functional requirements, non-functional requirements, explicit out-of-scope items, and two clarifying questions.",
      "minimum_chars" => 40
    },
    {
      "id" => "slos_constraints",
      "label" => "Set SLOs and constraints",
      "minutes" => 5,
      "brief" => "Make the design measurable and safe before choosing storage. Account for latency, availability, correctness, authorization, and abuse boundaries.",
      "artifact_prompt" => "State two SLOs, three hard constraints, and one security or abuse assumption that would change the design.",
      "minimum_chars" => 40
    },
    {
      "id" => "capacity_estimates",
      "label" => "Estimate capacity",
      "minutes" => 8,
      "brief" => "Turn the requirements into an order-of-magnitude capacity model. Keep assumptions visible so the interviewer can challenge one without invalidating the whole design.",
      "artifact_prompt" => "Show request rate, peak multiplier, storage growth, and one bottleneck estimate with units and assumptions.",
      "minimum_chars" => 40
    },
    {
      "id" => "high_level_design",
      "label" => "Draw the high-level design",
      "minutes" => 10,
      "brief" => "Describe the request path from client to durable state, an external boundary, and a status read. Keep the source of truth and asynchronous work explicit.",
      "artifact_prompt" => "Write the components and one end-to-end request sequence, including where the authoritative state is first enforced.",
      "minimum_chars" => 40
    },
    {
      "id" => "deep_dive_data_api",
      "label" => "Deep dive on data and API",
      "minutes" => 10,
      "brief" => "Choose the state model and API contract. Explain how a retry, a concurrent duplicate, and an external callback map to durable records and observable responses.",
      "artifact_prompt" => "Provide a compact schema, two API examples, and the state transitions for one successful and one retry or duplicate request.",
      "minimum_chars" => 40
    },
    {
      "id" => "failures_tradeoffs",
      "label" => "Defend failures and trade-offs",
      "minutes" => 5,
      "brief" => "An external dependency times out and asynchronous work is delayed. Defend how your design detects ambiguity, recovers, and makes the trade-off observable.",
      "artifact_prompt" => "Write a failure matrix with two recovery actions, one observable signal, and the trade-off you would revisit first.",
      "minimum_chars" => 40
    },
    {
      "id" => "summary_next_step",
      "label" => "Summarize and choose the next check",
      "minutes" => 2,
      "brief" => "Close the design as you would in an interview: state the decision, the most important caveat, and the next experiment or capacity check.",
      "artifact_prompt" => "Write a concise recommendation, one caveat, and one verification step that would earn confidence before launch.",
      "minimum_chars" => 40
    }
  ].freeze
  CAREER_PHASES = [
    {
      "id" => "opening_narrative", "label" => "Open with a truthful narrative", "minutes" => 5,
      "brief" => "Give a concise introduction, name the role fit, and separate verified experience from a claim that needs confirmation.",
      "artifact_prompt" => "Write a 60–90 second opening, one evidence boundary, and one clarifying question you would ask before making a stronger claim.",
      "minimum_chars" => 40
    },
    {
      "id" => "project_evidence", "label" => "Defend project evidence", "minutes" => 12,
      "brief" => "Walk through one real project or repository boundary. State what the code or records establish, what is inferred, and what you would measure next.",
      "artifact_prompt" => "Write a STAR/CARE project answer with the verified contribution, observed result, limitation, and one counterexample or failure mode.",
      "minimum_chars" => 40
    },
    {
      "id" => "follow_up_audience_shift", "label" => "Adapt to the audience and challenge", "minutes" => 8,
      "brief" => "Answer a difficult follow-up for a recruiter, engineer, staff interviewer, or stakeholder. Change the level of detail without changing the evidence boundary.",
      "artifact_prompt" => "Write short, medium, and deep versions of the same answer, then state the condition that would make you revise it.",
      "minimum_chars" => 40
    },
    {
      "id" => "feynman_rephrase", "label" => "Feynman and rephrase", "minutes" => 5,
      "brief" => "Teach the decision plainly, name a reasoning error you might have made, and rephrase the conclusion for a non-specialist.",
      "artifact_prompt" => "Explain the decision to a teammate, identify a false premise or missing evidence, and give one actionable Black Box repair.",
      "minimum_chars" => 40
    }
  ].freeze
  INTERVIEW_PHASES = [
    {
      "id" => "opening_context", "label" => "Opening and context", "minutes" => 8,
      "brief" => "Answer the opening naturally, define the problem, and ask for the missing constraint before narrowing the claim.",
      "artifact_prompt" => "Write an opening, the actor and success condition, two assumptions, and one clarification question.",
      "minimum_chars" => 40
    },
    {
      "id" => "technical_project_deep_dive", "label" => "Technical/project deep dive", "minutes" => 20,
      "brief" => "Defend a technical or project decision with evidence, an alternative, a trade-off, and a failure mode. Do not invent ownership or impact.",
      "artifact_prompt" => "Write a project deep dive with verified claims, inference/assumption/unknown labels, two options or a hard constraint, and one observable signal.",
      "minimum_chars" => 40
    },
    {
      "id" => "follow_up_uncertainty", "label" => "Follow-up and uncertainty", "minutes" => 10,
      "brief" => "Handle an adversarial follow-up. Update the decision when new evidence changes the premise and calibrate certainty rather than defending a slogan.",
      "artifact_prompt" => "Write the challenge, your updated answer, the evidence that changed it, and the trigger that would change it again.",
      "minimum_chars" => 40
    },
    {
      "id" => "close_reflection", "label" => "Close and reflect", "minutes" => 7,
      "brief" => "Close with the decision, caveat, next check, and what you would change now. Leave listening and speech assessment to the external platform.",
      "artifact_prompt" => "Write a concise close, one limitation, one next experiment, and a Feynman/Black Box reflection on your reasoning.",
      "minimum_chars" => 40
    }
  ].freeze
  PHASES_BY_TARGET = {
    "dsa" => DSA_PHASES,
    "system_design" => SYSTEM_DESIGN_PHASES,
    "career" => CAREER_PHASES,
    "rails_experience" => INTERVIEW_PHASES,
    "go_experience" => INTERVIEW_PHASES,
    "elixir_experience" => INTERVIEW_PHASES,
    "interview" => INTERVIEW_PHASES
  }.freeze
  MOCK_SCENARIO_BRIEFS = {
    "dsa_mock_01" => "Coding problem: Given an integer array values and k, return the length of the longest contiguous subarray containing at most k distinct values. The intended solution should make the window invariant and duplicate handling testable.",
    "dsa_mock_02" => "Coding problem: Given a stream of timestamped events, a duration window, and a threshold, return every event key whose count in the trailing window reaches the threshold. State how out-of-order timestamps are handled and keep the implementation bounded.",
    "dsa_mock_03" => "Coding problem: Given item names with frequencies and an integer k, return the k most frequent names with deterministic lexicographic tie-breaking. The interviewer expects a defensible heap or sorting choice and tests for ties.",
    "system_design_mock_01" => "Design scenario: Build an idempotent payment-intake and payment-status service that calls an external provider without charging twice when clients retry.",
    "system_design_mock_02" => "Design scenario: Build a webhook ingestion and reconciliation service for a payment provider whose callbacks can be duplicated, delayed, or missing while operators need an auditable status.",
    "system_design_mock_03" => "Design scenario: Build a multi-tenant URL shortener with custom aliases, abuse controls, redirects at high read volume, and a durable analytics path that cannot block redirects."
  }.freeze
  CAREER_BREAKDOWN = [ [ "opening narrative", 5 ], [ "project evidence", 12 ], [ "follow-ups and audience shift", 8 ], [ "Feynman and rephrase", 5 ] ].freeze
  INTERVIEW_BREAKDOWN = [ [ "opening and context", 8 ], [ "technical/project deep dive", 20 ], [ "follow-up and uncertainty", 10 ], [ "close and reflection", 7 ] ].freeze

  def self.build_mock(id, day, target, mode, duration, required_card_keys, breakdown, constraints)
    scenario = MOCK_SCENARIO_BRIEFS[id.to_s]
    phases = PHASES_BY_TARGET.fetch(target.to_s, []).map do |phase|
      scenario ? phase.merge("brief" => "#{scenario} #{phase.fetch('brief')}") : phase
    end
    required_sequence = required_card_keys.each_with_index.flat_map do |card_key, index|
      [
        {
          "step" => index * 2,
          "card_key" => card_key,
          "attempt_kind" => "initial",
          "content_variant_id" => "initial",
          "parent_step" => nil
        },
        {
          "step" => index * 2 + 1,
          "card_key" => card_key,
          "attempt_kind" => "follow_up",
          "content_variant_id" => "follow_up",
          "parent_step" => index * 2
        }
      ]
    end
    {
      "id" => id,
      "day" => day,
      "target" => target,
      "mode" => mode,
      "duration_minutes" => duration,
      "required_card_keys" => required_card_keys,
      "required_sequence" => required_sequence,
      "breakdown" => breakdown,
      "constraints" => constraints,
      "phases" => phases
    }.freeze
  end
  private_class_method :build_mock

  # A mock is deliberately a data record, rather than a controller branch.
  # This makes the same sequence available to the launcher, finish contract,
  # and progress gates.
  MOCK_SPECS = [
    build_mock("gate_d07_career", 7, "career", "timed_30", 30, [
      "career-01-a-60-to-90-second-introduction",
      "career-05-short-medium-and-deep-compression",
      "career-08-star-and-care-framing"
    ], CAREER_BREAKDOWN, [ "initial answer <= 90s", "name evidence boundary", "invite one follow-up" ]),
    build_mock("dsa_mock_01", 11, "dsa", "timed_45", 45, [ "dsa-03-complexity-defence" ], DSA_BREAKDOWN, [ "pattern <=3m", "code <=20m", "defend complexity" ]),
    build_mock("gate_d14_rails_experience", 14, "rails_experience", "timed_45", 45, [
      "rails_experience-03-payment-performance-and-safe-rollout",
      "rails_experience-07-study-cockpit-committed-release-evidence",
      "rails_experience-08-settleflow-idempotency-and-locks"
    ], INTERVIEW_BREAKDOWN, [ "separate verified claim from hypothesis", "include rollback or recovery", "adapt one answer" ]),
    build_mock("system_design_mock_01", 15, "system_design", "timed_45", 45, [ "system_design-03-source-of-truth" ], SYSTEM_DESIGN_BREAKDOWN, [ "requirements first", "state source of truth", "name consistency trade-off" ]),
    build_mock("gate_d21_go_elixir", 21, "interview", "timed_45", 45, [
      "go_experience-03-fulfillhub-local-transaction-and-outbox-delivery",
      "go_experience-07-pixrail-claim-before-spi-side-effect",
      "elixir_experience-01-pulseops-transactional-enqueue",
      "elixir_experience-05-reportforge-staged-artifact-compensation"
    ], INTERVIEW_BREAKDOWN, [ "switch language boundary without translating", "state evidence limit", "answer one difficult follow-up" ]),
    build_mock("dsa_mock_02", 22, "dsa", "timed_45", 45, [ "dsa-07-tradeoff-language" ], DSA_BREAKDOWN, [ "compare two valid approaches", "state invariant", "defend a reversal condition" ]),
    build_mock("system_design_mock_02", 23, "system_design", "timed_45", 45, [ "system_design-06-failure-modes" ], SYSTEM_DESIGN_BREAKDOWN, [ "enumerate failure modes", "bound retries", "name an observable signal" ]),
    build_mock("dsa_mock_03", 27, "dsa", "timed_45", 45, [ "dsa-05-clarifying-question" ], DSA_BREAKDOWN, [ "clarify before coding", "state edge cases", "compress the conclusion" ]),
    build_mock("system_design_mock_03", 28, "system_design", "timed_45", 45, [ "system_design-07-tradeoff-defence" ], SYSTEM_DESIGN_BREAKDOWN, [ "defend one trade-off", "name what would change the choice", "close with verification" ]),
    build_mock("interview_rehearsal", 29, "interview", "timed_45", 45, [
      "career-03-an-engineering-introduction",
      "rails_experience-07-study-cockpit-committed-release-evidence",
      "go_experience-03-fulfillhub-local-transaction-and-outbox-delivery",
      "elixir_experience-01-pulseops-transactional-enqueue",
      "general-09-incident-update",
      "general-10-handling-unknowns"
    ], INTERVIEW_BREAKDOWN, [ "recruiter-to-engineer shift", "no invented metric", "ask for the missing constraint" ]),
    build_mock("interview_final", 30, "interview", "timed_45", 45, [
      "career-01-a-60-to-90-second-introduction",
      "rails_experience-03-payment-performance-and-safe-rollout",
      "go_experience-07-pixrail-claim-before-spi-side-effect",
      "elixir_experience-05-reportforge-staged-artifact-compensation",
      "career-07-recruiter-engineer-staff-stakeholder-adaptation",
      "general-12-interview-close"
    ], INTERVIEW_BREAKDOWN, [ "60–90 second opening", "cross-target follow-up", "close with an evidence-bounded next step" ])
  ].freeze

  DAY_ASSIGNMENTS = [
    [ "general-01-introduction", "dsa-01-pattern-naming", "ruby-01-blocks-vs-procs", "rails-01-n-plus-one", "react-01-state-ownership", "career-01-a-60-to-90-second-introduction", "rails_experience-01-early-rails-integrations-and-geospatial-work" ],
    [ "golang-01-interface-placement", "elixir-01-process-model", "databases-01-modeling-constraints", "go_experience-01-backend-service-template-memory-idempotency", "elixir_experience-01-pulseops-transactional-enqueue", "system_design-01-requirements-first" ],
    [ "dsa-02-invariant-statement", "career-02-a-recruiter-introduction", "rails_experience-02-a-growing-ecommerce-api" ],
    [ "ruby-02-method-lookup", "career-03-an-engineering-introduction", "rails_experience-03-payment-performance-and-safe-rollout" ],
    [ "rails-02-transaction-boundaries", "career-04-a-chronological-walkthrough", "rails_experience-04-application-security-and-idor" ],
    [ "react-02-effect-misuse", "career-05-short-medium-and-deep-compression", "rails_experience-05-recent-volume-finance-and-messaging" ],
    [ "golang-02-goroutine-leak", "career-06-role-fit-and-why-now", "rails_experience-06-job-search-dashboard-retries-and-throttling" ],
    [ "elixir-02-let-it-crash", "career-07-recruiter-engineer-staff-stakeholder-adaptation", "rails_experience-07-study-cockpit-committed-release-evidence" ],
    [ "databases-02-indexes-workload", "career-08-star-and-care-framing", "rails_experience-08-settleflow-idempotency-and-locks" ],
    [ "system_design-02-volume-estimation", "career-09-a-difficult-metric-follow-up", "rails_experience-09-flowbridge-recovery-and-ssrf" ],
    [ "dsa-03-complexity-defence", "career-10-clarification-before-commitment", "rails_experience-10-rediscraft-reactor-and-aof" ],
    [ "general-06-star-conflict", "career-11-confidentiality-safe-handling", "rails_experience-11-ractorized-rails-research-boundary" ],
    [ "ruby-04-memory-allocation", "career-12-what-i-would-change-now", "rails_experience-12-activerecord-optimizer-validation" ],
    [ "rails-03-idempotent-jobs", "go_experience-02-bankport-concurrent-idempotency-middleware", "elixir_experience-02-pulseops-per-tenant-queue-limit" ],
    [ "system_design-03-source-of-truth", "go_experience-03-fulfillhub-local-transaction-and-outbox-delivery", "elixir_experience-03-pulseops-terminal-reconciliation" ],
    [ "react-04-data-fetching", "go_experience-04-gocachelab-aof-durability-and-recovery", "elixir_experience-04-reportforge-inflight-cancellation" ],
    [ "golang-03-context-propagation", "go_experience-05-kubepulse-policy-and-level-triggered-reconciliation", "elixir_experience-05-reportforge-staged-artifact-compensation" ],
    [ "elixir-05-back-pressure", "go_experience-06-pixguard-atomic-screening-and-outbox-leases", "elixir_experience-06-reportforge-stream-first-boundary" ],
    [ "databases-03-explain-query-plans", "go_experience-07-pixrail-claim-before-spi-side-effect", "elixir_experience-07-reconpulse-atomic-replay-request" ],
    [ "general-09-incident-update", "go_experience-08-rinha-go-exact-knn-scaling-boundary", "elixir_experience-08-reconpulse-webhook-failure-circuit-risk" ],
    [ "dsa-04-ruby-default-trap", "go_experience-09-terraport-lifecycle-import-and-ambiguous-retry", "elixir_experience-09-reconpulse-broker-and-ssrf-boundaries" ],
    [ "dsa-07-tradeoff-language", "rails_experience-13-supportnest-deterministic-routing-experiments", "go_experience-10-tokenforge-deterministic-byte-bpe-boundary" ],
    [ "system_design-06-failure-modes", "rails_experience-14-fiscalbridge-provider-boundary", "go_experience-11-tracebridge-bounded-admission-and-retry-stall" ],
    [ "databases-06-replication-lag", "rails_experience-15-openbank-simulation-boundary", "go_experience-12-trustvault-secret-lifecycle-and-ssrf-boundary" ],
    [ "ruby-05-gvl-concurrency", "rails_experience-16-ticketboard-clean-architecture-tradeoff", "elixir_experience-10-rinha-elixir-supervised-resource-reload" ],
    [ "rails-08-migration-safety", "rails_experience-17-railsdoctor-context-and-redaction-boundary", "elixir_experience-11-rinha-elixir-exact-knn-scaling-baseline" ],
    [ "general-04-respectful-disagreement", "rails_experience-18-solidlens-explain-hypothesis-boundary", "elixir_experience-12-rinha-elixir-genserver-serialization-risk" ],
    [ "elixir-04-supervision-strategy", "rails_experience-19-rinha-rails-versus-ruby-knn-study", "rails_experience-20-local-review-tooling-pipeline-boundaries" ],
    [],
    []
  ].freeze

  GATE_DAYS = [ 7, 14, 21, 30 ].freeze

  class << self
    def plan
      DAY_ASSIGNMENTS.each_with_index.map do |item_ids, index|
        day = index + 1
        {
          "day" => day,
          "title" => title_for(day),
          "outcome" => outcome_for(day),
          "timebox_minutes" => 90,
          "assignment" => {
            "targets" => item_ids.map { |item_id| target_for(item_id) }.uniq,
            "item_ids" => item_ids.dup,
            "selector" => selector_for(day)
          },
          "srs_review" => {
            "due" => day == 1 ? "baseline capture" : "review due cards before new production",
            "required" => true
          },
          "follow_up" => { "required" => true, "minimum" => day >= 29 ? 2 : 1 },
          "compression" => { "required" => true, "minimum" => 1 },
          "reattempt" => { "required" => true, "delayed" => day >= 8 },
          "interleaving" => day >= 3 ? "alternate technical reasoning with narrative or project evidence" : "establish one target at a time",
          "weak_area_remediation" => "Use the lowest self-rubric axis to choose the next rephrase or Black Box repair.",
          "spaced_reattempts" => spaced_reattempts_for(day),
          "mocks" => mocks_for(day),
          "gate" => gate_for(day)
        }.compact
      end
    end

    def target_for(item_id)
      prefix = item_id.to_s.split("-", 2).first
      return "system_design" if prefix == "system_design"

      CANONICAL_TARGETS.include?(prefix) || prefix == "salesforce" ? prefix : nil
    end

    def mock(id)
      spec = MOCK_SPECS.find { |candidate| candidate.fetch("id") == id.to_s }
      spec && deep_dup(spec)
    end

    def mocks_for(day)
      MOCK_SPECS.select { |spec| spec.fetch("day") == day.to_i }.map { |spec| deep_dup(spec) }
    end

    def phases_for(target)
      PHASES_BY_TARGET.fetch(target.to_s, []).map { |phase| deep_dup(phase) }
    end

    def phases_for_mock(mock_id, target)
      scenario = MOCK_SCENARIO_BRIEFS[mock_id.to_s]
      phases_for(target).map do |phase|
        scenario ? phase.merge("brief" => "#{scenario} #{phase.fetch('brief')}") : phase
      end
    end

    def phase_for(target, phase_id)
      phases_for(target).find { |phase| phase.fetch("id") == phase_id.to_s }
    end

    # Keep the 90% floor in integer seconds. A float such as 0.9 * 5.minutes
    # can admit a sub-second early completion on different adapters.
    def minimum_phase_seconds(phase)
      phase.fetch("minutes").to_i * 54
    end

    def phase_state_valid?(spec, state, session_started_at:, expires_at:, now: Time.current)
      phases = Array(spec.is_a?(Hash) ? spec["phases"] : nil)
      return false if phases.empty? || !state.is_a?(Hash) || !session_started_at || !expires_at

      state = state.to_h.transform_keys(&:to_s)
      index = state["current_index"].to_i
      checkpoints = Array(state["checkpoints"]).map { |checkpoint| checkpoint.to_h.transform_keys(&:to_s) }
      return false unless index == phases.length && checkpoints.length == phases.length

      previous_completed_at = nil
      valid_checkpoints = checkpoints.each_with_index.all? do |checkpoint, checkpoint_index|
        phase = phases.fetch(checkpoint_index)
        started_at = parse_phase_timestamp(checkpoint["started_at"])
        completed_at = parse_phase_timestamp(checkpoint["completed_at"])
        artifact = checkpoint["artifact"].to_s.strip
        valid = checkpoint["phase_id"].to_s == phase.fetch("id") &&
          checkpoint["phase_index"].to_i == checkpoint_index &&
          artifact.length >= phase.fetch("minimum_chars").to_i &&
          checkpoint["artifact_length"].to_i == artifact.length &&
          started_at && completed_at &&
          (completed_at - started_at) >= minimum_phase_seconds(phase) &&
          completed_at <= now && completed_at <= expires_at &&
          started_at >= session_started_at && started_at <= expires_at &&
          (checkpoint["elapsed_seconds"].to_f - (completed_at - started_at)).abs < 1.0 &&
          (previous_completed_at.nil? || started_at >= previous_completed_at)
        valid &&= (started_at - session_started_at).abs < 1.0 if checkpoint_index.zero?
        previous_completed_at = completed_at if valid
        valid
      end
      return false unless valid_checkpoints
      return false unless state["current_phase_started_at"].nil?

      completed_at = parse_phase_timestamp(state["completed_at"])
      last_completed_at = parse_phase_timestamp(checkpoints.last&.[]("completed_at"))
      completed_at && last_completed_at && (completed_at - last_completed_at).abs < 0.001
    rescue ArgumentError, TypeError, KeyError
      false
    end

    def required_mock_ids_through(day)
      MOCK_SPECS.select { |spec| spec.fetch("day") <= day.to_i }.map { |spec| spec.fetch("id") }
    end

    def required_item_ids_through(day)
      DAY_ASSIGNMENTS.first(day.to_i).flatten.uniq
    end

    def required_delayed_item_variant_ids_through(day)
      DAY_ASSIGNMENTS.first(day.to_i).each_with_index.flat_map do |_item_ids, index|
        scheduled_day = index + 1
        next [] unless (8..20).cover?(scheduled_day)

        spaced_reattempts_for(scheduled_day).filter_map do |reattempt|
          item_id = reattempt["item_id"].to_s.presence
          variant_id = reattempt["variant_id"].to_s.presence
          next unless item_id && variant_id

          "#{item_id}:#{variant_id}"
        end
      end.uniq
    end

    def required_delayed_item_ids_through(day)
      required_delayed_item_variant_ids_through(day).map { |item_variant_id| item_variant_id.split(":", 2).first }.uniq
    end

    def gate_for(day)
      return nil unless GATE_DAYS.include?(day.to_i)

      required_mock_ids = required_mock_ids_through(day)
      required_item_ids = required_item_ids_through(day)
      id = { 7 => "gate_d07_career", 14 => "gate_d14_rails_experience", 21 => "gate_d21_go_elixir", 30 => "interview_final" }.fetch(day.to_i)
      {
        "id" => "gate_d#{day.to_i.to_s.rjust(2, "0")}",
        "accept" => "All required assignments and named mocks have reproducible production evidence.",
        "fail" => "A required item, metric, follow-up, delayed retest, or named mock is still missing.",
        "thresholds" => {
          "meaningful_typed" => [ required_item_ids.length, 1 ].max,
          "practice_days" => { 7 => 6, 14 => 12, 21 => 18, 30 => 26 }.fetch(day.to_i),
          "canonical_coverage" => CANONICAL_TARGETS.length,
          "due_reviews" => [ day.to_i - 1, 1 ].max,
          "critical_pairs" => { 7 => 6, 14 => 13, 21 => 20, 30 => 26 }.fetch(day.to_i),
          "critical_targets" => { 7 => 6, 14 => 13, 21 => 13, 30 => 13 }.fetch(day.to_i),
          "critical_target_pair_counts" => day.to_i == 30 ? CANONICAL_TARGETS.to_h { |target| [ target, 2 ] } : {},
          "follow_up_completed" => { 7 => 6, 14 => 13, 21 => 20, 30 => 26 }.fetch(day.to_i),
          "delayed_retest_eligible" => { 7 => 0, 14 => 7, 21 => 13, 30 => 13 }.fetch(day.to_i),
          "delayed_retest_rate" => { 7 => 0.0, 14 => 0.0, 21 => 0.0, 30 => 0.8 }.fetch(day.to_i),
          "technical_accuracy" => 0.65,
          "required_mock_ids" => required_mock_ids,
          "required_item_ids" => required_item_ids,
          "required_delayed_item_variant_ids" => required_delayed_item_variant_ids_through(day)
        },
        "required_mock_counts" => MOCK_SPECS.select { |spec| spec.fetch("day") <= day.to_i }.group_by { |spec| spec.fetch("target") }.transform_values(&:length),
        "required_mock_anchor" => id,
        "recovery" => {
          "assignment" => "Repeat the missing item or mock with closed-book production, Feynman, and Black Box when wrong.",
          "retest_after_days" => 7,
          "steps" => [ "identify the failing evidence", "reattempt without translation", "repeat after seven days" ]
        }
      }
    end

    private

    def parse_phase_timestamp(value)
      return if value.nil? || value.to_s.empty?

      Time.iso8601(value.to_s)
    end

    def deep_dup(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested_value), copy|
          copy[deep_dup(key)] = deep_dup(nested_value)
        end
      when Array
        value.map { |nested_value| deep_dup(nested_value) }
      when String
        value.dup
      else
        value
      end
    end

    def title_for(day)
      return "Baseline capture" if day <= 2
      return "Cross-target interview rehearsal" if day >= 29

      "Evidence, precision, and adaptive follow-ups"
    end

    def outcome_for(day)
      return "Capture one closed-book production item for each canonical target." if day <= 2
      return "Run a named mock, then use SRS and reflection to close the highest-risk gap." if day >= 29

      "Answer naturally, defend the decision, and record a precise next experiment."
    end

    def selector_for(day)
      return "Launch the named cross-target mock, then complete SRS and reflection." if day >= 29
      return "Capture one closed-book item for each listed baseline target." if day <= 2

      "Launch each listed item; complete the follow-up, compression, and delayed reattempt."
    end

    def spaced_reattempts_for(day)
      return [] unless (8..20).cover?(day.to_i)

      item_id = BASELINE_ITEM_IDS.fetch(day.to_i - 8)
      [
        {
          "item_id" => item_id,
          "target" => target_for(item_id),
          "original_day" => BASELINE_ITEM_IDS.index(item_id).to_i < 7 ? 1 : 2,
          "attempt_kind" => "retry",
          "variant_id" => "delayed_variant",
          "changed_evidence_required" => true,
          "public_prompt" => false
        }
      ]
    end
  end
end
