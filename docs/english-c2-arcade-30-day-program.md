# English C2 Arcade: executable 30-day program

Status date: 2026-08-25. This document describes the pending local expansion.
It is not evidence that the expansion has been deployed, that the learner has
completed it, or that the learner has reached CEFR C2. The production service
continues to run the prior release until the release gate records a new commit
and deployment.

## Scope and evidence boundary

The program is typed, closed-book, self-rated interview practice. It covers the
eight technical tracks (`ruby`, `rails`, `react`, `golang`, `elixir`,
`databases`, `system_design`, and `dsa`), General Conversation, Career
Narrative, and evidence-bounded Rails, Go, and Elixir project experience.
Salesforce remains a 1.0 legacy/elective pack: it is launchable for practice,
but is explicitly critical-ineligible and never counts toward canonical
readiness or a gate.

The transversal critical-thinking contract applies to the 13 canonical targets,
164 items and 39 canonical cards. Every qualifying item must separate verified
facts, inferences, assumptions and gaps; frame the problem; ask clarifying
questions; compare alternatives; test a counterexample or failure mode;
calibrate certainty; and revise the decision when evidence changes. Salesforce
does not enter this contract or its credit counters.

English Arcade does not record or assess listening, microphone input,
pronunciation, spontaneous speech, or overall CEFR level. The five language
axes are optional learner self-ratings attached to typed production. When
supplied, the server validates their range; they are report-only and never
change correctness, quality, Leitner, mastery or gate state. Technical accuracy
is reported separately and uses only the eight technical tracks. Typed semantic
reasoning remains `not_assessed`. The external platform handoff is documented in
`docs/english-c2-arcade-sources-and-handoff.md`.

## Daily execution contract

Every day is timeboxed to 90 minutes. The UI is the executable source of truth;
the server, not query parameters, owns item target, mock order, duration, and
gate identity.

1. Review due Leitner cards before new production.
2. Answer the scheduled interviewer question closed-book and in English.
3. Commit a meaningful typed answer; optionally add the five self-ratings.
4. Write the Feynman explanation before any answer or provenance is revealed.
5. Read feedback for register, hedging, precision, grammar, and pragmatics.
6. Complete all five actionable Black Box fields after a miss.
7. Produce at least one follow-up and one compressed or audience-adapted
   version.
8. Schedule or complete the delayed reattempt. A delayed-retention event counts
   only after at least seven days and only for the canonical scheduled item.

The closed loop is server-observable: commit freezes the prompt variant,
opaque option tokens and content digest; Feynman precedes reveal; a wrong
answer requires an actionable Black Box before scheduling; and reattempts use
their own authored follow-up or delayed variant. Mastery requires two
high-quality critical variants with distinct digests and at least seven days
between them. Rephrase, compression and extension remain visible practice but
never create critical credit. A mock must include the server-owned challenge,
the correct sequence and the required defence artifacts; elapsed time alone is
not enough.

Days 1–2 establish the exact baseline: one fixed item for each of the 13
canonical targets. Baseline status remains pending if any item is missing or if
an item is persisted under the wrong target. Language-axis evidence and
technical-knowledge evidence are deliberately separate; neither is an overall
C2 diagnosis.

## Calendar

The stable IDs below are launchable from the in-product plan. Days 3–28 contain
exactly two new experience items per day; all 56 experience items appear once.
Days 29–30 reserve new-item time for cross-target interview mocks.

| Day | New closed-book items | Official mock / gate |
|---:|---|---|
| 1 | `general-01-introduction`; `dsa-01-pattern-naming`; `ruby-01-blocks-vs-procs`; `rails-01-n-plus-one`; `react-01-state-ownership`; `career-01-a-60-to-90-second-introduction`; `rails_experience-01-early-rails-integrations-and-geospatial-work` | Baseline A |
| 2 | `golang-01-interface-placement`; `elixir-01-process-model`; `databases-01-modeling-constraints`; `go_experience-01-backend-service-template-memory-idempotency`; `elixir_experience-01-pulseops-transactional-enqueue`; `system_design-01-requirements-first` | Baseline B; exact 13-target baseline closes |
| 3 | `dsa-02-invariant-statement`; `career-02-a-recruiter-introduction`; `rails_experience-02-a-growing-ecommerce-api` | — |
| 4 | `ruby-02-method-lookup`; `career-03-an-engineering-introduction`; `rails_experience-03-payment-performance-and-safe-rollout` | — |
| 5 | `rails-02-transaction-boundaries`; `career-04-a-chronological-walkthrough`; `rails_experience-04-application-security-and-idor` | — |
| 6 | `react-02-effect-misuse`; `career-05-short-medium-and-deep-compression`; `rails_experience-05-recent-volume-finance-and-messaging` | — |
| 7 | `golang-02-goroutine-leak`; `career-06-role-fit-and-why-now`; `rails_experience-06-job-search-dashboard-retries-and-throttling` | `gate_d07_career` (30m); gate D7 |
| 8 | `elixir-02-let-it-crash`; `career-07-recruiter-engineer-staff-stakeholder-adaptation`; `rails_experience-07-study-cockpit-committed-release-evidence` | — |
| 9 | `databases-02-indexes-workload`; `career-08-star-and-care-framing`; `rails_experience-08-settleflow-idempotency-and-locks` | — |
| 10 | `system_design-02-volume-estimation`; `career-09-a-difficult-metric-follow-up`; `rails_experience-09-flowbridge-recovery-and-ssrf` | — |
| 11 | `dsa-03-complexity-defence`; `career-10-clarification-before-commitment`; `rails_experience-10-rediscraft-reactor-and-aof` | `dsa_mock_01` (45m) |
| 12 | `general-06-star-conflict`; `career-11-confidentiality-safe-handling`; `rails_experience-11-ractorized-rails-research-boundary` | — |
| 13 | `ruby-04-memory-allocation`; `career-12-what-i-would-change-now`; `rails_experience-12-activerecord-optimizer-validation` | — |
| 14 | `rails-03-idempotent-jobs`; `go_experience-02-bankport-concurrent-idempotency-middleware`; `elixir_experience-02-pulseops-per-tenant-queue-limit` | `gate_d14_rails_experience` (45m); gate D14 |
| 15 | `system_design-03-source-of-truth`; `go_experience-03-fulfillhub-local-transaction-and-outbox-delivery`; `elixir_experience-03-pulseops-terminal-reconciliation` | `system_design_mock_01` (45m) |
| 16 | `react-04-data-fetching`; `go_experience-04-gocachelab-aof-durability-and-recovery`; `elixir_experience-04-reportforge-inflight-cancellation` | — |
| 17 | `golang-03-context-propagation`; `go_experience-05-kubepulse-policy-and-level-triggered-reconciliation`; `elixir_experience-05-reportforge-staged-artifact-compensation` | — |
| 18 | `elixir-05-back-pressure`; `go_experience-06-pixguard-atomic-screening-and-outbox-leases`; `elixir_experience-06-reportforge-stream-first-boundary` | — |
| 19 | `databases-03-explain-query-plans`; `go_experience-07-pixrail-claim-before-spi-side-effect`; `elixir_experience-07-reconpulse-atomic-replay-request` | — |
| 20 | `general-09-incident-update`; `go_experience-08-rinha-go-exact-knn-scaling-boundary`; `elixir_experience-08-reconpulse-webhook-failure-circuit-risk` | — |
| 21 | `dsa-04-ruby-default-trap`; `go_experience-09-terraport-lifecycle-import-and-ambiguous-retry`; `elixir_experience-09-reconpulse-broker-and-ssrf-boundaries` | `gate_d21_go_elixir` (45m); gate D21 |
| 22 | `dsa-07-tradeoff-language`; `rails_experience-13-supportnest-deterministic-routing-experiments`; `go_experience-10-tokenforge-deterministic-byte-bpe-boundary` | `dsa_mock_02` (45m) |
| 23 | `system_design-06-failure-modes`; `rails_experience-14-fiscalbridge-provider-boundary`; `go_experience-11-tracebridge-bounded-admission-and-retry-stall` | `system_design_mock_02` (45m) |
| 24 | `databases-06-replication-lag`; `rails_experience-15-openbank-simulation-boundary`; `go_experience-12-trustvault-secret-lifecycle-and-ssrf-boundary` | — |
| 25 | `ruby-05-gvl-concurrency`; `rails_experience-16-ticketboard-clean-architecture-tradeoff`; `elixir_experience-10-rinha-elixir-supervised-resource-reload` | — |
| 26 | `rails-08-migration-safety`; `rails_experience-17-railsdoctor-context-and-redaction-boundary`; `elixir_experience-11-rinha-elixir-exact-knn-scaling-baseline` | — |
| 27 | `general-04-respectful-disagreement`; `rails_experience-18-solidlens-explain-hypothesis-boundary`; `elixir_experience-12-rinha-elixir-genserver-serialization-risk` | `dsa_mock_03` (45m) |
| 28 | `elixir-04-supervision-strategy`; `rails_experience-19-rinha-rails-versus-ruby-knn-study`; `rails_experience-20-local-review-tooling-pipeline-boundaries` | `system_design_mock_03` (45m) |
| 29 | No new item; due SRS, repair, and reflection only | `interview_rehearsal` (45m) |
| 30 | No new item; due SRS, repair, and reflection only | `interview_final` (45m); gate D30 |

DSA mocks preserve the method-source phase minutes `[5, 8, 20, 8, 4]`:
clarify/invariant, pattern/approach, code/test, complexity/follow-up, and
Feynman/Black Box. System Design preserves `[5, 5, 8, 10, 10, 5, 2]`:
requirements, SLO/constraints, estimates, high-level design, data/API deep
dive, failures/trade-offs, and summary.

The three DSA scenarios are an at-most-`k`-distinct sliding window, a bounded
trailing-window event threshold, and top-`k` frequency with deterministic
lexicographic ties. The three System Design scenarios are idempotent payment
intake/status, webhook ingestion plus reconciliation, and a multi-tenant URL
shortener. Each phase displays that mock's scenario and requires its own typed
artifact. The server owns phase order, start/completion timestamps and the
append-only checkpoint ledger; it accepts a phase only after exactly 90% of
that phase's timebox and verifies that the stored artifact length matches the
artifact. Client-supplied phase indexes or elapsed times are ignored. An
expired session rejects new phases and cannot satisfy a progress gate.

The 30-day contract is 30 daily 90-minute sessions, 11 phased named mocks, and
13 scheduled delayed variants across D8–D20. D7 deliberately has zero delayed
credit: its gate measures critical pairs and target coverage before the first
seven-day reattempt can qualify. The server also requires the exact named mock, card sequence, target, mode,
initial-attempt kind, meaningful typed production, Feynman marker and text,
feedback reveal, Black Box after a miss, and at least 90% of the overall timed
window. Before Feynman reveal, history says only `Feedback locked`; correctness,
the answer and provenance are not rendered. Every canonical item has its own
authored follow-up and compression prompt. Only an actual `follow_up` attempt
increments the gate's follow-up count; compression, rephrase and extension
remain separately visible adaptation evidence.

## Acceptance gates

All item and mock requirements are cumulative and use intersections with the
canonical assignment IDs, canonical target pairings and scheduled delayed
items. IDs are unique at gate time: repeated attempts on one item and outsider
cards cannot inflate a gate. A future gate stays `pending`; a reached gate with
insufficient evidence is `fail`, not an optimistic pass.

| Gate | Critical pairs | Critical targets | Delayed eligible items | Delayed success |
|---|---:|---:|---:|---:|
| D7 | 6 | ≥6 | 0 | not assessed |
| D14 | 13 | 13 | 7 | schedule evidence |
| D21 | 20 | 13 | 13 | schedule evidence |
| D30 | 26 | ≥2 per canonical target | 13 | ≥80% |

Every gate also requires its cumulative canonical assignment/mock contract and
its server-observable evidence. Metrics expose their source and
`assessment_scope`: `fact_contract` is authored-reference evidence, artifact
fields are structural observations, Brier is based on the learner's confidence
choice only, and self-rubric is report-only. These are practice thresholds, not
validated CEFR cut scores. Failure recovery is: identify the missing evidence,
reattempt closed-book without translation, complete Feynman and an actionable
Black Box when required, then repeat the variant after seven days.

## Real-project provenance inventory

The four experience packs contain 56 items, 102 verified-claim entries, 171
exact file-at-commit references, and 56 explicit confirmation gaps. Each item
stores project/repository, evidence class, verified claims, confirmation
requirements, a safe interview version, and a confidentiality risk. The risk
labels are conservative interview controls; they do not mean secret material
was copied into the pack. Current labels are 27 high, 28 medium, and 1 low.

- Rails/Ruby: five secondary résumé-derived career stories plus Job Search
  Dashboard, System Design Study Cockpit, SettleFlow, FlowBridge, Rediscraft,
  Ractorized Rails Kernel, Active Record Optimizer, SupportNest, FiscalBridge,
  OpenBank Sandbox, TicketBoard, RailsDoctor, SolidLens, the Rails/Ruby Rinha
  studies, and the four-tool local review pipeline.
- Go: Backend Service Template, BankPort, FulfillHub, GoCacheLab, KubePulse,
  PixGuard, PixRail, Rinha Go, Terraport, TokenForge, TraceBridge, and
  TrustVault.
- Elixir: PulseOps, ReportForge, ReconPulse, and the Rinha Elixir reference
  implementation.

Repository evidence proves only the named code, documentation, test, benchmark
or decision artifact at the cited commit. It does not prove employer
production use, authorship share, external users, business outcomes, historical
metrics, current operation, or a current successful test run. Résumé-derived
claims remain secondary transcriptions because the referenced résumé PDF is
absent. The user must confirm each listed gap before using the claim in an
interview; portfolio/challenge work must never be presented as employer
production work.

The per-item provenance map is the structured `provenance` object in:

- `db/seeds/english_arcade/career.yml`;
- `db/seeds/english_arcade/rails-experience.yml`;
- `db/seeds/english_arcade/go-experience.yml`; and
- `db/seeds/english_arcade/elixir-experience.yml`.

It is hidden from the learner before the Feynman reveal and rendered through a
field whitelist afterward. No token, credential, `.env` value, PII payload, or
secret file is part of the map.

## Readiness decision

The local product contract can be called ready only after the repository-wide
verification and fresh independent review pass. The current production
deployment remains the older Railway deployment
`6f07bd3e-30e3-4c76-ae78-cd7f64cd38c7`; this critical-thinking expansion is
not committed or deployed. Deployment readiness is a separate gate requiring
a committed SHA, successful Railway deployment, and authenticated production
smoke. Learner interview readiness cannot be decided
before the learner supplies the baseline and D7/D14/D21/D30 evidence. Even a
passing D30 practice gate is not mathematical proof of CEFR C2 or a guarantee
of interview success.
