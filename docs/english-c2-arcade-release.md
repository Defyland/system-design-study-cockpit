# English C2 Arcade release checklist

> Historical prior-release record: any deployment, local-count, or 8/96/1080
> evidence below describes the earlier release only. This pending expansion is
> not deployed and must not be represented as current production evidence until
> its release checks are recorded.

This is a release gate for the English-first interview-learning path in the
cockpit. It describes practice evidence and a 30-day route; it must never say
that the product guarantees CEFR C2 in 30 days.

The exact daily calendar, baseline, mock catalogue, gate thresholds and
project-provenance inventory are in
`docs/english-c2-arcade-30-day-program.md`.

## Contract under test

The historical fixture at
`test/english_arcade/fixtures/english_c2_arcade.yml` is the executable content
legacy compatibility evidence. It requires exactly eight target packs and does
not define current canonical coverage.

The pending expansion contract (not current production) has 14 selectable
packs, 176 items and 42 Leitner cards. Thirteen packs are canonical: the eight
technical tracks, General Conversation, Career Narrative, and the Rails, Go
and Elixir Experience packs. They total 164 canonical items. Salesforce is
directly selectable but is a 1.0 legacy/elective pack: it is
critical-ineligible and never supplies critical credit. The launcher exposes 16 choices: 14 packs
plus mixed and interview. Browser voice capture is absent: typed production
only, with an external-platform handoff boundary for any speaking/listening
work.

The transversal critical-thinking contract is therefore 13 canonical targets,
164 items and 39 canonical cards. Each critical item requires a server-observed
problem frame, evidence classifications, a comparison or rejected alternative,
a counterexample/failure mode, a confidence choice and a change-my-mind signal.
Typed semantic reasoning is `not_assessed`; fact-contract accuracy, structural
artifact presence and confidence-choice Brier evidence retain separate sources
and `assessment_scope` values. Self-rubric is optional, validated when supplied
and report-only; it cannot alter correctness, quality, Leitner, mastery or a
gate.

The `fact_contract` metric is authored-reference evidence; artifact fields are
structural observations and Brier is based on the learner's confidence choice
only.

Every item has a natural interview prompt, context, one complete answer, at
least two plausible distractors, register/hedging/precision/grammar/pragmatics
feedback, rephrase/follow-up/compression prompts, Feynman and actionable Black
Box work, recall metadata, and a source reference. The four experience packs
also require structured file-at-commit provenance, verified claims,
confirmation gaps, a safe interview version and confidentiality risk. DSA and
System Design each expose three official 45-minute mocks. The system-design
pack links to the `system-design-estudos` corpus by repository and path; it does
not copy the corpus into the app.

All 164 canonical items require authored follow-up and compression prompts;
the seven core technical packs contain 168 item-specific adaptive prompts for
their 84 items. Exact duplicates, conservative repeated n-grams, non-question
follow-ups, non-actionable compressions and answer leakage fail validation.
Canonical production packs are authoritative at runtime: a missing, malformed
or loader-failed pack stays unavailable and is never replaced by a generic
fixture.

The fixture validator rejects missing fields, duplicate IDs, invalid source
references, answer/distractor collisions, answer text in learner-visible
fields, missing corpus links, fewer than 12 items, and incorrect timed-mode
configuration.

## Learning state machine

The implementation must preserve these states and transitions:

`idle → active_recall → feynman → feedback → scheduled → reattempt`.

An error may branch from `feedback` through `black_box` before `scheduled`.
`reattempt` may return to `feynman` or reach `mastered`; `mastered` is terminal.
It must not jump from `idle`, `active_recall`, or `feedback` directly to
`mastered`.

The learning loop is:

- closed-book active recall;
- a Feynman explanation after an attempt;
- a Black-Box post-mortem after an error;
- Leitner scheduling; and
- a reattempt that preserves the selected target.

Leitner boxes use 1/2/4/7/14 days for boxes 1–5. A wrong answer resets to box
1; a correct answer advances one box. Commit freezes opaque answer tokens,
variant and content digest; Feynman precedes reveal; follow-up and delayed
variants have their own prompts; and future prompts are not projected into an
initial snapshot. Mastery requires at least 8/10 on two critical variants with
distinct digests separated by at least seven days. Rephrase, compression and
extension remain practice-only. A score is practice evidence, not a CEFR
assessment.

## Rails and persistence gates

- [ ] `GET /english-arcade` renders `section.english-arcade[data-controller='english-arcade']`
  and semantic target/session-length radio groups. The pending launcher has
  16 choices: 14 packs plus mixed and interview; Salesforce is elective.
- [ ] Saving a target persists `target_key`; reloading the launcher selects the
  same target, and the next item comes from that target.
- [ ] An attempt, Feynman text, Black-Box text, score, confidence, target,
  attempt number, and timestamps survive a reload.
- [ ] A wrong attempt creates a box-1 schedule; a correct attempt advances one
  box without creating duplicate schedule identities.
- [ ] The answer key and reveal-only container are absent from the initial
  learner DOM and prompt snapshot; feedback/answer text appears only after the
  closed-book attempt/reveal boundary (the strongest answer remains a visible
  multiple-choice candidate by design).
- [ ] The import path stores target-linked material as structured records, and
  the normal search path finds an imported target item without embedding a
  second standalone React build.
- [ ] The 30-day plan contains 30 daily 90-minute sessions, an exact 13-item
  baseline, all 56 experience items once, two new experience items on each day
  D3–D28, and no new assignments on D29–D30.
- [ ] Eleven named mocks are server-authoritative and phased. Ordinary timed sessions do
  not count; altered target/mode/anchor/order, duplicate/outsider attempts,
  missing typed/Feynman/Black Box evidence, a missing challenge/defence, or less
  than 90% elapsed time fail closed. Thirteen scheduled delayed variants run
  across D8–D20; D7 delayed credit is exactly zero.
- [ ] The six DSA/System Design mocks use distinct scenario briefs and an
  ordered server-time phase ledger. Every phase requires a typed artifact,
  exactly 90% of its own timebox, matching stored length and immutable order;
  early, reordered, duplicated, tampered or expired submissions do not mutate
  qualifying evidence.
- [ ] Unrevealed history exposes neither correctness nor answer/provenance.
  Follow-up gates count only `follow_up`; compression, rephrase and extension
  remain separate adaptation metrics.
- [ ] Gates D7/D14/D21/D30 use unique canonical assignment IDs, target
  intersections and scheduled delayed IDs; repetitions and outsider cards do
  not count. Their critical thresholds are D7 `6 pairs / ≥6 targets / 0
  delayed`, D14 `13 / 13 / 7`, D21 `20 / 13 / 13`, and D30 `26 / ≥2 per target
  / 13`, with D30 delayed success `≥80%`. Future gates stay pending; reached
  deficient gates fail and expose a seven-day recovery path.

## Critical evidence contract

For every canonical critical item the learner follows closed-book attempt →
Feynman → feedback → actionable Black Box after an error → Leitner/SRS →
reattempt. The server accepts only `initial`, `follow_up` and `delayed_variant`
for critical evidence and mastery; other adaptations remain visible but cannot
inflate critical counters. Metrics distinguish authored facts, observed
artifact structure, report-only self-rubric, and unassessed semantic reasoning.
The contract is fail-closed for incomplete critical artifacts, wrong lineage,
future-prompt leakage, digest reuse, and reveal-before-Feynman.

## Accessibility and responsive gates

- [ ] Target selection and answer submission use native labels/controls or an
  equivalent accessible name; there are no pointer-only actions.
- [ ] Focus remains visible, Enter submits where appropriate, and Space reveals
  only after an attempt.
- [ ] Buttons and inputs remain usable at 44 CSS pixels minimum touch size.
- [ ] The system test checks 390×844, 768×1024, and 1440×1000 without horizontal
  overflow; normal vertical page growth remains scrollable.
- [ ] A screen-reader pass verifies stage announcements, error feedback, and
  the reattempt affordance. The product is typed-only; any external speaking
  assessment is outside this application and is not a scored CEFR feature.

## Content import, search, and health gates

- [ ] `Content::Importer` can import a representative target item, checkpoint,
  progress row, and source attribution idempotently.
- [ ] `StudySearch` returns the imported item by prompt/source text and does
  not expose the hidden answer in learner controls.
- [ ] `/up` returns 200 after boot.
- [ ] `/health/content` returns 200 with `status`, `study_documents`,
  `content_bootstrapped`, and `latest_sync_status` after a successful content
  sync; a failed/degraded sync is visible and blocks a green release claim.

## Verification commands

Run from `system-design-study-cockpit`:

```sh
ruby -Itest/english_arcade -e 'require "english_arcade_fixture_validator"; v=EnglishArcade::FixtureValidator.new(EnglishArcade::FixtureValidator.load_fixture); abort(v.errors.join("\n")) unless v.valid?; puts "fixture contract valid"'
ruby lib/english_arcade/validate.rb
bin/rails test test/english_arcade/canonical_pack_contract_test.rb test/english_arcade/fixture_contract_test.rb test/english_arcade/rails_contract_test.rb
bin/rails test test/models/english_arcade_card_test.rb
bin/rails test test/system/english_arcade_flow_test.rb test/system/english_arcade_accessibility_test.rb
bin/rails routes | grep -E '(/up|english-arcade|health/content)'
bin/rails test test/controllers/health_checks_controller_test.rb test/services/content_importer_test.rb test/services/study_search_test.rb
bin/brakeman --no-pager
bin/bundler-audit check --update
```

The first command is intentionally runnable without booting Rails. The Rails
and system commands must be reported with their exact result. Do not convert a
missing local dependency, a skipped browser run, or an unavailable deployment
credential into a PASS.

## Historical fallback evidence (superseded 2026-08-23)

This records the Composer-replacement handoff before the final System Design
pack and mechanics/health work landed. It is retained for provenance; the
current release result is the green local gate below.

The scoped fallback initially ran these commands from the cockpit checkout:

- `ruby -c` over all scoped Arcade Ruby tests: PASS (`Syntax OK` for each
  file).
- The standalone fixture validator: PASS (`96 items across 8 targets`).
- `ruby lib/english_arcade/validate.rb`: initially FAIL (exit 1); DSA, Ruby, Rails,
  React, and Golang are publishable at 12 items/3 cards each, while Elixir,
  Salesforce, and System Design packs are missing (`5/8 packs valid, 60 items,
  15 cards`). This is a hard release blocker.
- `bin/rails test test/english_arcade/canonical_pack_contract_test.rb
  test/english_arcade/fixture_contract_test.rb
  test/english_arcade/rails_contract_test.rb`: initially FAIL (exit 1); the fixture and
  persistence/import/health tests pass, but the canonical gate fails on the
  three missing packs.
- `bin/rails test test/system/english_arcade_flow_test.rb
  test/system/english_arcade_accessibility_test.rb`: PASS (4 runs, 45
  assertions); visible-label target selection, keyboard answer selection,
  strict five-field Black Box completion, reattempt, and mobile/tablet/desktop
  overflow checks all pass.
- `bin/rails test test/models/english_arcade_card_test.rb`: PASS (3 runs, 19
  assertions), covering exact Leitner intervals and two-variant mastery
  spacing.
- `bin/rails routes | grep -E '(/up|english-arcade|health/content)'`: PASS;
  launcher, session/attempt POST, `/up`, and `/health/content` routes are
  present.
- `bin/rails test test/controllers/health_checks_controller_test.rb
  test/services/content_importer_test.rb test/services/study_search_test.rb`:
  PASS (20 runs, 74 assertions).
- `bin/brakeman --no-pager`: exit 5 because installed Brakeman 8.0.5 is not
  the latest 8.0.6; no green security claim is made.
- `bin/bundler-audit check --update`: FAIL (exit 1) with advisories for
  Active Storage, json, loofah, mail, rails-html-sanitizer, and
  websocket-driver; deployment remains blocked until dependencies are patched.

`RAILS_ENV=test bin/rails db:migrate` was run once to apply the concurrently
landed `20260823010200_add_english_arcade_black_box_fields` migration before
the browser rerun.

Those handoff failures were resolved by the final pack rescue, canonical
adapter handoff, and mechanics seat; see the current local gate evidence.

## Deployment gate

- [x] Record the tested commit SHA and Railway deployment ID without printing
  credentials or private database values.
- [x] Verify production `/up`, `/health/content`, `/english-arcade`, target
  selection, one wrong-answer Black-Box path, one reattempt, and a reload of
  the saved target.
- [x] Confirm the imported document count and latest successful sync in the
  health payload.
- [ ] Confirm rollback can restore the previous release without deleting
  attempts or schedules.

### Production evidence (2026-08-23)

The tested runtime commit is `2a7ea22` (`Add English C2 Arcade interview
path`). Railway deployment `088a4cf2-3e97-43ef-8748-4849f4c84d5e` reached
`SUCCESS` from a clean detached worktree. A documentation-only follow-up
commit `6d29972` was then published as deployment
`a49d7f7b-4a70-450c-b003-4c63b9121a14`, also reaching `SUCCESS`. Authenticated
production smoke on the runtime release
returned HTTP 200 for `/up`, `/health/content`, `/english-arcade`, and the JSON
export. The health response was `status=ok` with
`english_arcade_pack_readiness.ready=true`. The JSON projection contained 30
plan days and no `correct_choice` or `answer_text` before reveal. A bounded
authenticated React session verified target persistence after reload, a
deliberately wrong answer, the required Feynman reveal, a five-field Black Box
post-mortem, and a box-1 scheduled reattempt. No credentials or private
database values are included here.

The canonical answer-key rotation fix is commit `e6c6011` (`Keep canonical
Arcade answer keys stable`), deployed from a clean worktree as
`6f07bd3e-30e3-4c76-ae78-cd7f64cd38c7` with `SUCCESS`. A fresh production React
session then accepted the canonical answer, revealed `correct=true`, and
advanced the card to box 2 with a 2-day interval.

Rollback was not exercised against live traffic; doing so would change the
published service for no additional feature evidence. Railway retains the
previous successful deployment for an operator-led rollback, and no migration
or seed step deletes attempts or schedules.

## Historical deployed-release local gate evidence (2026-08-23)

The content and local application gates are green:

```text
Historical pre-expansion validator evidence: 8/8 packs, 96 items, 24 cards
english_arcade:validate / qa / health               valid; pack_minima_ready=true; status=ok
corpus import (first and second run)                 1080 records, 334 links, persisted_documents=0 on both runs
focused content/import/search/health tests           14 runs, 107 assertions, 0 failures, 0 errors
focused Rails/system Arcade suite                   13 runs, 115 assertions, 0 failures, 0 errors, 0 skips
system flow/accessibility                            4 runs, 45 assertions, 0 failures, 0 errors
full Rails suite                                      116 runs, 1614 assertions, 0 failures, 0 errors, 0 skips
RuboCop                                               157 files, no offenses
HTTP smoke (local Puma)                               /up 200; /health/content 200; /english-arcade 200; JSON export safe
```

The publication and live target/session checks are complete; only the
operator-led rollback exercise remains intentionally unverified.

## Pending expansion local pre-review gate (historical pre-critical scope, 2026-08-23)

This evidence belongs to the 14-pack expansion in the current worktree. It is
not production evidence and does not authorize release before the fresh
independent review.

```text
standalone pack validator                         14/14 packs; 176 items; 42 cards; canonical 13/164/39
english_arcade validate / QA / health             1,160 records; 367 links; ready=true; warnings=[]
dry import run 1 / run 2                           byte-identical; persisted_documents=0 on both
full Rails suite                                   169 runs; 5,523 assertions; 0 failures/errors/skips
system flow/accessibility                          8 runs; 68 assertions; 0 failures/errors/skips
RuboCop                                             163 files; no offenses
Brakeman 8.0.6                                      0 security warnings
bundler-audit / importmap audit                     updated advisory DB; no vulnerabilities
Zeitwerk / Ruby YAML syntax / Stimulus syntax       PASS
authenticated local HTTP                           /up 200; health 200; Arcade HTML/JSON 200
unauthenticated local HTTP                          Arcade 401 on serial verification
learner JSON/HTML                                   30 days; 16 targets; no answer/provenance/SHA leak
```

The first cold local smoke intentionally issued several development-mode
requests concurrently and one request raced route reloading, returning a
transient 404. Serial repeats returned the expected `401/200/200` for
unauthenticated HTML, authenticated HTML and authenticated JSON. Production
eager loading and the later Railway smoke remain separate evidence gates.

Brakeman initially reported one weak `Marshal.load` warning in curriculum
copying. The implementation was replaced with recursive copying, a mutation
regression was added, and both the focused suite and Brakeman rerun passed.

## Critical-thinking expansion focused evidence (2026-08-25)

The following is the current uncommitted local handoff after the transversal
critical-thinking/runtime corrections. It is focused evidence only, not a full
repository suite and not production evidence:

```text
content validator / pack contracts                  14/14 packs; 176 items; 42 cards; canonical 13/164/39
controller regressions                               27 runs; 387 assertions; 0 failures/errors
card + Rails + progress + validator                 38 runs; 193 assertions; 0 failures/errors
critical contract suites                             33 runs; 1,494 assertions; 0 failures/errors
Ruby syntax / scoped git diff check                 PASS
```

The focused evidence does not authorize a commit, deployment or C2 claim. A
fresh independent Sol review is still pending. The current production runtime
remains Railway deployment `6f07bd3e-30e3-4c76-ae78-cd7f64cd38c7`; this
critical-thinking expansion has not been committed or deployed.

## Known limitations and current fallback

Real speech scoring is not part of this gate. Browser speech capture is absent;
the product accepts typed production only and does not assess pronunciation or
listening. The product cannot certify CEFR C2, and a 30-day path is a
calibration and practice promise only. Production uses the app's existing
shared Basic Auth boundary and an anonymous/username-derived learner key;
per-account identity and privacy isolation are future work if the cockpit
becomes multi-user.

Composer seat creation failed before execution because the desktop model
validator rejected the requested Composer reasoning combination. The assigned
Luna MAX regression/test fallback owns these tests and this checklist. No
Composer analysis, edits, or participation is claimed.
