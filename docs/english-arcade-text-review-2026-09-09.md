# Arcade text review — 2026-09-09

Status: local review, corrections and integration checks completed. This document does not establish a production release.

## Scope and criteria

The review covers all learner text in the 14 live source packs (176 items and
42 flashcards), the resume-profile overrides and 12 role-specific interview
cards, their 48 reasoning questions, the study calendar, and the guidance used
by the Arena and legacy interview screens. Repository engineering documents,
test fixtures and the linked external study corpus are not new learner content
authored by this review.

Three native subagents use GPT-5.6-Luna with maximum reasoning effort. They own
separate content files; the controller owns shared runtime guidance, integration
checks and the coverage record. Existing unrelated work and the earlier local
draft, warmup and role-question features remain part of the baseline.

For each learner answer, the editorial questions are:

- Does it answer this specific question in natural first-person language?
- Does the choice follow from the actual requirement and available evidence?
- Are benefits, costs, alternatives and switching conditions concrete where a choice exists?
- Does a failure case or proposed check test the decision rather than decorate it?
- Are verified experience, inference, assumption and proposed action distinct?
- Does the changed-question answer adapt to the changed condition?
- Does each distractor retain its intended flaw, with an accurate explanation?

First person applies to model answers and card backs. Instructions can address
the learner; intentionally flawed distractors retain their educational role.
The checks do not claim to measure learning gains, semantic quality or fluency.

## Initial observations

A structural census of the original 14 packs found 678 model-answer fields
(including flashcard backs and available answer versions). Of these, 105 lacked
first-person wording. Twenty-four contained one of three repeated generic
reasoning tails. These counts locate issues; they are not substitutes for reading
the content or evaluating the technical decision.

The controller's guidance review found:

- The Meet instruction encouraged a single read without identifying what needed explanation. It now asks for the fact or decision being explained, with a reason, cost and switching condition when a choice is involved. Short factual answers do not need an invented trade-off.
- The legacy evidence ledger said not to fact-check oneself. It now asks the learner to distinguish established facts, inference and assumptions, and mark details for verification.
- The local transcript coach invited judgments about audio properties unavailable in text. Its prompt now marks pronunciation, pace, pauses and spoken fluency as not assessed.
- The audio coach described all authored material as truth. Its reference instructions now preserve the distinction between verified facts, assumptions and proposed checks.
- The analytics caption described all selections grouped by an axis as wrong answers. Its label and explanation now describe what those counts actually represent.
- Arena exercise identity depended on a schema version rather than the current answer. Content fingerprints now bind open lessons to the text they presented; revised content uses the existing stale-content rejection path.
- Feynman and compression used the unexplained label "satellite". Their instructions now state the learning action, and each answer field has an explicit label.
- Completion wording now describes exercise checks and practice records, without presenting those checks as complete command of the subject.

The source check found that the current frontend PDF differs from its stored
fingerprint. Its Bornlogic section still supports the eight microfrontends,
five squads, deployment-time reduction and seven-to-two-second list example.
The Smart TV and full-stack PDFs match their stored fingerprints. All three
describe the delivery metric as "deploy time"; the review therefore keeps it as
deployment time rather than assuming a release lead-time definition. The PDFs
remain local and are not bundled with the application.

Technical reference used for the external-payment boundary:
[Stripe idempotent requests](https://docs.stripe.com/api/idempotent_requests).
Its provider-side replay contract is distinct from a uniqueness constraint in
the application's own database. The related Rails transaction/job boundary is
documented in [Active Job Basics](https://guides.rubyonrails.org/active_job_basics.html#transactional-integrity-on-jobs).

## Coverage and evidence

The three initial lane reports enumerate every source-pack item and card ID.
The coverage checker confirms each ID appears in exactly one owning review.
Counts below compare source packs with the clean HEAD baseline for these files;
an unchanged item was reviewed but did not require an edit.

| Pack | Items reviewed | Items changed | Cards reviewed | Cards changed |
| --- | ---: | ---: | ---: | ---: |
| career | 12 | 0 | 3 | 3 |
| databases | 12 | 12 | 3 | 3 |
| dsa | 12 | 11 | 3 | 3 |
| elixir-experience | 12 | 12 | 3 | 3 |
| elixir | 12 | 12 | 3 | 3 |
| general | 12 | 1 | 3 | 3 |
| go-experience | 12 | 12 | 3 | 3 |
| golang | 12 | 12 | 3 | 3 |
| rails-experience | 20 | 8 | 3 | 3 |
| rails | 12 | 12 | 3 | 3 |
| react | 12 | 12 | 3 | 3 |
| ruby | 12 | 12 | 3 | 3 |
| salesforce | 12 | 3 | 3 | 3 |
| system-design | 12 | 12 | 3 | 3 |
| Total | 176 | 131 | 42 | 42 |

The final model-field census covers 678 fields: zero lack first-person wording
and zero retain the three detected generic reasoning tails. All source item and
card IDs and their order are preserved. These lexical checks are regression
checks, not an automated judgment of reasoning quality.

The resume pass also read all 12 canonical profiles, the 12 role-specific cards
and their 48 reasoning questions. It corrected the deployment metric and source
fingerprint, separated verified experience from proposed implementation, and
made recommendation confidence depend on role constraints and technical evidence.
The curriculum, calendar and mock-study text was read without requiring an edit.

## Substantive corrections

- Ruby and Elixir: concrete runtime mechanisms, ownership, workload assumptions,
  recovery boundaries and the measurement that could change a recommendation.
- DSA: invariants, input constraints, complexity and counterexamples tied to the
  actual algorithm instead of a generic demand to compare tools.
- Rails, databases and Go: local transactions and unique constraints are distinct
  from an external provider's effects; changed idempotency input, crash recovery,
  reconciliation and concurrency limits are explicit where relevant.
- React: state ownership, effect cleanup, server writes after browser abort,
  keyboard/focus behavior, measured render costs, auth recovery and deterministic
  hydration each have their own decision criteria.
- System Design: estimates identify assumptions; cache collapse distinguishes
  same-key coalescing from global admission; pending payment acceptance requires
  a product policy; a fresh balance read does not itself prevent racing debits;
  partitioning one oversized tenant onto another primary does not divide its load.
- Career and language coaching: examples use the learner's first-person reasoning,
  while claims about experience stay within supplied evidence. Text-only coaching
  marks pronunciation, pace, pauses and spoken fluency as not assessed.

The later critical-field pass replaced generic claim maps, comparisons, certainty
and rubrics across Ruby, Elixir, DSA, Elixir experience, React and System Design.
Questions with a factual distinction can explicitly reject a false comparison;
they do not need artificial pros and cons.

## Independent review and runtime corrections

The first cross-review rejected generic critical scaffolding left by the initial
pass. Owners then rewrote those fields and submitted exact-ID completion reports.
A separate review read all 12 System Design scenarios and their revised critical
fields; its remaining ambiguous compression sentence was corrected. The final
DSA/Elixir-experience review covered all 23 remediated blocks without a material
finding. The Ruby/Elixir review covered all 24 blocks and found three issues:
allocation evidence was confused with frozen-literal semantics, and two authored
stories were framed as learner facts. The affected probe, framing and certainty
fields now separate semantic ownership from performance, and authored examples
from verified personal experience. The independent reviewer then confirmed
all six corrected fields and reported no remaining findings in that bounded pass.

The runtime cross-review found that a failed JSON refresh could lose the
`stale_content` error and offer Retry against obsolete material. The controller
now carries that error to a terminal updated-material view, hides the obsolete
exercise and links back to Arena. The already-saved exercise result remains
recorded. A system regression test exercises that boundary after a successful save.
HTML visits to stale lessons show the same recovery direction. Content identity
uses a canonical content fingerprint so answer edits cannot silently replace the
material associated with an open lesson.

Other review findings removed a universal checklist from short factual answers
and replaced run-on generated trade-off text with readable, punctuated paragraphs.
Targeted tests cover the prompt boundary and the exact generated comparison.

Additional primary references used during the review:

- [React effect synchronization](https://react.dev/reference/react/useEffect)
- [React render error boundaries](https://react.dev/reference/react/Component#catching-rendering-errors-with-an-error-boundary)
- [React hydration](https://react.dev/reference/react-dom/client/hydrateRoot)
- [WAI-ARIA menu button pattern](https://www.w3.org/WAI/ARIA/apg/patterns/menu-button/)
- [Ruby Ractor](https://ruby-doc.org/3.4.1/Ractor.html)
- [Elixir processes](https://elixir-lang.org/getting-started/processes.html)

## Validation and limits

- Strict standalone content validation: 14/14 packs, 176 items and 42 cards passed,
  including the final three editorial corrections.
- Integrated service/controller/content suite: 294 tests, 31,603 assertions,
  zero failures/errors/skips. This ran after writer freeze and before the final
  six-field Ruby/Elixir wording correction; final content checks cover that delta.
- RuboCop: 14 affected Ruby files inspected, zero offenses.
- Node syntax checks: eight changed guidance/controller modules passed.
- Exact-ID review coverage: all 14 source packs, 176 items and 42 cards passed.
- Browser/system suite on the final text: 24 tests, 286 assertions, zero
  failures/errors/skips. This includes saved-result/stale-refresh recovery,
  draft retry and restoration, keyboard access and responsive layouts.
- Final content-quality suite after the six-field correction: 13 tests,
  10,098 assertions, zero failures/errors/skips.
- Final `git diff --check`: passed. The seven protected dashboard/library/search
  diffs retain the exact baseline SHA-256
  `01b018575684e07bdb3dbe90a62eacc27e59b25ca4df15382cb678d86b2576ea`.

Local browser inspection covered frontend rehearsal, expanded alternative and
verification questions, the updated-material page, and a fresh System Design
lesson with its answer guide. The frontend layout was also inspected at a
390 px viewport; the visible lesson boxes fit within the 375 px content area
(the remainder is the scrollbar). These are sampled UI checks, not screenshots
of every exercise.

Capture record: local review captures covered the frontend rehearsal, the System
Design answer and guide, and updated-lesson recovery. The captures are retained
outside this repository and are intentionally not linked here.


This is a local editorial and implementation review. It does not establish a
production deployment, a measured learning improvement, a live audio session,
or a full audit of the linked external study corpus. Existing unrelated changes
in dashboard/library/search were preserved. No commit, push or publication was
performed in this round.
