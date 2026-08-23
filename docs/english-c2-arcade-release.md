# English C2 Arcade release checklist

This is a release gate for the English-first interview-learning path in the
cockpit. It describes practice evidence and a 30-day route; it must never say
that the product guarantees CEFR C2 in 30 days.

## Contract under test

The fixture at
`test/english_arcade/fixtures/english_c2_arcade.yml` is the executable content
contract. It requires exactly eight target packs, with 12 items in each pack:

`dsa`, `ruby`, `rails`, `react`, `golang`, `elixir`, `salesforce`, and
`system_design`.

Every item has a natural interview prompt, context, one answer, at least two
plausible distractors, register/hedging/precision/grammar/pragmatics feedback,
a rephrase prompt, an extension prompt, and a source reference. DSA and system
design also expose a 45-minute simulation mode. The system-design pack links to
the `system-design-estudos` corpus by repository and path; it does not copy the
corpus into the app.

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
1; a correct answer advances one box. Mastery requires at least 8/10 on two
attempts separated by about seven days where feasible. A score is practice
evidence, not a CEFR assessment.

## Rails and persistence gates

- [ ] `GET /english-arcade` renders `section.english-arcade[data-controller='english-arcade']`
  and semantic target/session-length radio groups with all eight targets.
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

## Accessibility and responsive gates

- [ ] Target selection and answer submission use native labels/controls or an
  equivalent accessible name; there are no pointer-only actions.
- [ ] Focus remains visible, Enter submits where appropriate, and Space reveals
  only after an attempt.
- [ ] Buttons and inputs remain usable at 44 CSS pixels minimum touch size.
- [ ] The system test checks 390×844, 768×1024, and 1440×1000 without horizontal
  overflow; normal vertical page growth remains scrollable.
- [ ] A screen-reader pass verifies stage announcements, error feedback, and
  the reattempt affordance. Speech capture is optional host capability, not a
  scored CEFR feature.

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
- [x] Confirm rollback can restore the previous release without deleting
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

## Local gate evidence (2026-08-23)

The content and local application gates are green:

```text
ruby lib/english_arcade/validate.rb                 8/8 packs, 96 items, 24 cards
english_arcade:validate / qa / health               valid; pack_minima_ready=true; status=ok
corpus import (first and second run)                 1080 records, 334 links, persisted_documents=0 on both runs
focused content/import/search/health tests           14 runs, 107 assertions, 0 failures, 0 errors
focused Rails/system Arcade suite                   26 runs, 1040 assertions, 0 failures, 0 errors, 0 skips
system flow/accessibility                            4 runs, 45 assertions, 0 failures, 0 errors
full Rails suite                                      115 runs, 1612 assertions, 0 failures, 0 errors, 0 skips
RuboCop                                               157 files, no offenses
HTTP smoke (local Puma)                               /up 200; /health/content 200; /english-arcade 200; JSON export safe
```

The deployment checkbox remains open until the tested commit is published and
the live target selector/session path is exercised against Railway.

## Known limitations and current fallback

Real speech scoring is not part of this gate: browser speech capture is an
optional transcript, not pronunciation or listening assessment. The product
cannot certify CEFR C2, and a 30-day path is a calibration and practice promise
only. Production uses the app's existing shared Basic Auth boundary and an
anonymous/username-derived learner key; per-account identity and privacy
isolation are future work if the cockpit becomes multi-user.

Composer seat creation failed before execution because the desktop model
validator rejected the requested Composer reasoning combination. The assigned
Luna MAX regression/test fallback owns these tests and this checklist. No
Composer analysis, edits, or participation is claimed.
