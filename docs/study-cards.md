# Study cards

Local implementation on base revision `b0f5d52` (working-tree changes, not deployed).

## Delivered behavior

`/study-cards` is linked from the cockpit navigation and the Arena. It offers new-card rounds of at most 50 items, a topic selector, resumable rounds and an explicit completed-card replay button. The reader has a compact mobile layout, native disclosure for optional rehearsal, a next button, leftward swipe and undo. Completing a reading is not recorded as an assessment or an accurate answer.

Round order and position live in PostgreSQL, scoped using the existing `ArcadeLearnerIdentity` contract. Reloading keeps progress. Empty pools stop; they never automatically fall back to completed cards. Completion in one topic removes that card from the pending portion of another round when opened. Position and card identity protect advance against duplicated/stale requests. Undo applies to the last advance in that round.

## Content and provenance

50 unique entries: 14 authored technical cards plus 36 existing resume interview questions/variants. Topics: Frontend 15, Backend 11, System design 2, Algorithms 2, English 2, Full-stack 9, Smart TV 9.

Five technical prompts are adapted from the user-supplied Rippling screenshots and link to the original Gourav Hammad report. Their answers are original teaching material, not attributed quotations. Other technical entries are labeled authored simulations. Resume material and variants reuse the existing project content and claim boundaries. This is a curated initial catalog, not an automatic URL ingestion or AI generation service. Replaying does not manufacture new wording.

Authored cards are in `config/study_cards.yml`; the catalog adapter reuses `ArcadeContent`. Adding content requires stable IDs and all displayed content fields. There is no new dependency, grading engine, automatic repetition schedule or speech service.

## Local setup

```sh
bin/rails db:migrate
RAILS_ENV=test bin/rails db:migrate
bin/rails server -b 127.0.0.1 -p 3117 -P tmp/pids/study-cards-preview.pid
```

The migration only adds `study_card_rounds`. Existing content, assessment tables and the seven pre-existing modified files were not edited by this change.

## Verification

```sh
bin/rails test test/controllers/study_cards_controller_test.rb test/system/study_cards_test.rb
bin/rubocop --cache false app/controllers/study_cards_controller.rb app/models/study_card_round.rb app/services/study_card_catalog.rb db/migrate/20260925010000_create_study_card_rounds.rb test/controllers/study_cards_controller_test.rb test/system/study_cards_test.rb
git diff --check
```

Acceptance run: 5 tests, 33 assertions, no failures/errors/skips. Real Rails/Puma/PostgreSQL and headless Chrome, without mocked persistence or content. Desktop and narrow-screen captures were visually inspected. The local development page was also opened through the Codex browser.

The mobile test dispatches touch events through the real Stimulus controller and checks persisted state after reload; physical-device gestures remain unverified. No production validation or deployment was performed.

Failure sensitivity:

- Before excluding completion from other rounds, the controller test found the already-completed `rippling-this` card (expected 0, actual 1).
- Before binding updates to card identity, a stale page consumed the replacement card at position zero (expected position 0, actual 1).
- A deliberate temporary mutation replaced `round.update!(position: round.position + 1)` with an unsaved in-memory assignment. Both browser tests failed on the next-card assertion, proving the UI tests depend on persisted advancement. The source was restored automatically. See `evidence/study-cards/mutation.txt`.

Captures: `tmp/screenshots/study-cards-desktop.png` and `tmp/screenshots/study-cards-mobile.png`.

## Complete library integration (September 25)

The initial 50-card catalog now includes all 14 existing Arcade tracks and every imported library document. The live corpus audit reports 3,188 cards: 50 initial entries, 504 original Arcade questions/variants, and 2,634 sections covering all 335 documents. Canonical answers, distractors, feedback, exercises and references are reused; existing material is not rewritten by a generator.

Ruby, Ruby on Rails, Golang, Elixir, React, DSA, databases, professional English, career, experience tracks, system design and Salesforce are selectable. Experience tracks also belong to their parent language. Library cards are available by document category and registered side track; technology labels derive from document titles/section headings. Consequently a multidisciplinary document can belong to more than one technology track. Counts are overlapping memberships, not distinct-card totals.

Library cards preserve the exact source Markdown, split at headings outside fenced code. Heading-only fragments remain attached to their content. Authored interview Q&A remains verbatim; explanatory documents are labeled as readings, not falsely presented as interview answers. Every library card links to the complete original document; links to other imported documents resolve inside the cockpit. Existing round IDs and the initial 50 card IDs are preserved.

Coverage can be reproduced with:

```sh
bin/rails runner script/verify_study_card_catalog.rb
bin/rails test test/controllers/study_cards_controller_test.rb test/system/study_cards_test.rb test/system/study_card_library_test.rb test/services/study_document_cards_test.rb
```

`evidence/study-cards/catalog.json` records coverage, original-answer equality, lossless reconstruction of every imported document, and parity with filesystem source documents. No content discrepancies were found. The initial browser regression failed because Ruby was absent from the selector. A read-only in-memory mutation dropping the first section of every document made the audit fail with text-loss reports (`catalog-mutation.txt`); it did not modify files or database records.

Final integration check: 8 tests / 54 assertions passed (seed 61302), with no failures, errors or skips. Ruby, Rails, Go and Elixir were selected through the actual browser UI; the original Ruby answer was asserted after reveal. A library document was rendered with its code block, opened in full, completed and reloaded. The progress update no longer constructs the entire catalog; doing so caused an avoidable save delay under the larger corpus. RuboCop on the seven changed Ruby files and `git diff --check` passed. Captures include `tmp/screenshots/study-cards-library.png` and `tmp/screenshots/study-cards-ruby.png`.
