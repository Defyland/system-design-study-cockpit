# English C2 Arcade corpus integration

> Historical prior-release record: references below to local or deployed pack
> counts describe the earlier release. The pending expansion has an evidence
> slot after root deployment verification; do not describe 14 packs / 176 items
> as current production before that verification.

The Arcade is an English-first practice layer over two existing sources:

- `../english-arcade/src/data/seed.ts` (the legacy falling-card game); and
- `../system-design-estudos` (the canonical system-design curriculum).

The executable learner calendar and evidence boundary are documented in
`docs/english-c2-arcade-30-day-program.md`; dated external sources and the
typed-only external-platform interface are in
`docs/english-c2-arcade-sources-and-handoff.md`.

The cockpit does not replace either source. `Content::EnglishArcadeImporter`
indexes stable IDs, relative source paths, checksums and relationships. It does
not copy the Markdown body or execute the legacy TypeScript. A future content
pack can be supplied as structured hashes (`external_records:`) or as a
machine-readable `config/english_arcade_content.yml` file.

## Pending expansion pack contract (2026-08-25; not deployed)

There are 14 selectable packs / 176 interview items / 42 production cards.
The 13 canonical packs total 164 items: the eight technical tracks, General
Conversation, Career Narrative, and the Rails, Go and Elixir Experience packs.
Salesforce is a 1.0 legacy/elective pack: it remains launchable but is
critical-ineligible and excluded from readiness, gates and mixed/interview core
credit. The launcher exposes 16 choices: 14 packs plus mixed and interview.
The older eight-target fixture is retained only as legacy compatibility
evidence. The browser accepts typed production; it has no voice capture,
microphone, speech recognition, pronunciation or listening assessment.
Every one of the 164 canonical items has an authored follow-up and compression
prompt. In particular, the 84 items across DSA, Ruby, Rails, React, Go, Elixir
and System Design now carry 168 item-specific prompts instead of runtime
boilerplate. Strict per-pack validation and a cross-pack duplicate/n-gram
oracle enforce that contract; an invalid canonical pack remains unavailable
rather than falling back to fixture content.

The critical-thinking contract covers all 13 canonical targets, 164 items and
39 canonical cards. It requires evidence classification, problem framing,
clarification, alternatives/trade-offs, counterexamples/failure modes,
certainty calibration and revision under new evidence. The closed loop is
attempt → Feynman → feedback → Black Box when needed → Leitner/SRS → reattempt;
commit/reveal freezes the opaque variant and digest, and future prompts are not
projected into an initial snapshot. Only `initial`, `follow_up` and
`delayed_variant` can produce critical evidence or mastery; rephrase,
compression and extension remain report-visible practice. Self-rubric is
optional and report-only, while typed semantic reasoning is `not_assessed`.
The plan is 30 daily 90-minute sessions with 11 phased mocks and 13 scheduled
delayed variants on D8–D20; D7 delayed credit is zero. Mock credit requires the
server-owned challenge, ordered sequence and defence artifacts, not elapsed
time alone.

## Stable identity

Every corpus path is addressed as:

```text
system-design-estudos:<relative source path>
```

For example:

```text
system-design-estudos:chapters/chapter-01-relational-scaling-and-operational-discipline.md
```

Legacy Arcade items use an anchor rather than a copied sentence:

```text
english-arcade:legacy:item:tech-deep-01
```

The source path is `src/data/seed.ts#tech-deep-01`, and the seed checksum is
retained as metadata. Re-running the import is therefore idempotent and a
changed source can be detected without changing its identity.

Structured interview packs use the same anchor discipline without importing
legacy sentence prose:

```text
english-arcade:packs/dsa/dsa-01-pattern-naming
```

The source path is `db/seeds/english_arcade/dsa.yml#dsa-01-pattern-naming`; the
YAML checksum is retained, and duplicate runs collapse on the stable source ID.

## Relationship index

The curriculum manifest is read as a graph. Chapter records link to their
lab, review card, suggested decision contrast, primary/complementary case,
foundations, notes, playbooks, simulations and bridge labs. The importer also
indexes all chapter labs, review cards, decision contrasts and capstones on
disk, including records that are not currently listed in a chapter entry.
Structured pack items add `pack_source` links only for references whose
repository is `system-design-estudos`; `original` pack references remain
metadata anchors and do not become copied corpus records.

Links are stored as metadata only when an existing `StudyDocument` has the same
`source_path`; no duplicate `StudyDocument` is created. The normal content sync
should run first, followed by the Arcade import, because the regular importer
owns Markdown and can legitimately rewrite document metadata on its next run.

## Commands

From `system-design-study-cockpit`:

```sh
bin/rails english_arcade:validate
bin/rails english_arcade:qa
bin/rails english_arcade:import
bin/rails english_arcade:manifest > /tmp/english-arcade-manifest.json
bin/rails english_arcade:health
QUERY="replica lag" TARGET=system_design bin/rails english_arcade:search
```

`english_arcade:import` updates only the `metadata.english_arcade` adapter
fields on already imported documents. It never writes to either source
repository. Set `ENGLISH_ARCADE_PERSIST=false` for a read-only manifest run.
`english_arcade:health` is a redacted adapter-side readiness payload: it reports
record/link totals, validation and warning counts, target/item counts, the
minimum of 12 items per target, required field names and missing targets. It
does not include prompt/answer/distractor/feedback values, database names or
other private values. The existing `/health/content` endpoint remains owned by
the application readiness service and now includes the redacted
`english_arcade_pack_readiness` summary. It never includes prompt, answer,
distractor, source path, commit, provenance claim, database-name, or other
private values. Canonical readiness is exactly 13 targets / 164 items; the
elective Salesforce pack is reported separately.

## Release QA checklist

- [ ] `bin/rails english_arcade:validate` passes with no missing source IDs or
      interview-pack fields.
- [ ] `bin/rails english_arcade:qa` reports unique IDs, relative record/link
      paths, stable link endpoints, `warnings_empty` and `pack_minima_ready`.
- [ ] `bin/rails english_arcade:health` reports a redacted pack readiness
      payload; require `pack_readiness.ready=true` before claiming all targets
      are released.
- [ ] `bin/rails study:sync_content` completes before the Arcade import.
- [ ] `bin/rails english_arcade:import` is run twice; the second run reports no
      additional metadata changes.
- [ ] Search returns a legacy Arcade item by its ID and a system-design record
      by chapter/lab/review/contrast/capstone path or title.
- [ ] Rails tests in `test/services/content/english_arcade*` and
      `test/integration/english_arcade*` pass.
- [ ] Existing dirty product/content files remain unchanged by this adapter.
- [ ] `/up` and `/health/content` are checked after deployment; source GitHub
      availability and `STUDY_CONTENT_GITHUB_REF` are recorded without tokens.
- [ ] Browser smoke covers keyboard-only search and the Arcade target/session
      flow at narrow and wide viewports. Search results should expose a visible
      title and source path, with no answer rendered in a selectable control.
- [ ] Performance is measured with the production-sized manifest. Keep the
      index in memory or cache it rather than parsing TypeScript per request;
      never issue one SQL query per link.

## Known limits and deployment notes

The adapter indexes structured metadata; it is not speech recognition, a CEFR
certification, or a claim that thirty days guarantees C2. Typed attempts can be
measured by the host application, but real speech scoring and pronunciation
assessment remain future work. Production still requires the GitHub API source,
the configured content reference and a successful content readiness check. A
GitHub outage can make a fresh sync unavailable; the last imported documents
remain the local read path, so deployment should keep the previous database and
never treat an empty remote response as a destructive sync.

Accessibility and performance QA belong to the Arcade/UI worker, but the
integration contract is explicit: source IDs and links must be keyboard- and
screen-reader discoverable in the rendered result, while imported metadata must
remain bounded (IDs and paths, not full source prose).

## Historical pre-expansion QA evidence (2026-08-23)

The scoped checks were run against the current workspace after applying all
four additive English Arcade migrations required by the Rails test environment.
The counts below are an evidence snapshot; rerun them after future content
changes.

```text
RAILS_ENV=test bin/rails db:migrate              PASS
bin/rails english_arcade:validate                valid=true, records=1080, links=334, warnings=[]
bin/rails english_arcade:qa                      valid=true; unique IDs/paths/link endpoints/relative paths; warnings_empty=true; pack_minima_ready=true
bin/rails english_arcade:health                  status=ok, records=1080, links=334, validation_error_count=0, missing_targets=0
bin/rails english_arcade:import                   records=1080, links=334, persisted_documents=0
bin/rails english_arcade:import (second run)      records=1080, links=334, persisted_documents=0
scoped Rails tests                               14 runs, 107 assertions, 0 failures, 0 errors
```

Cross-app smoke on Puma returned `/up`, `/health/content`, and
`/english-arcade` successfully after the normal `bin/rails db:migrate` check.
The content health response is redacted and includes pack readiness; it does
not expose the database name or pack answers.

Historical pre-expansion evidence: the canonical `test/english_arcade/canonical_pack_contract_test.rb` gate then
reported 8/8 production targets present, 12 items and 3 cards each. The
fixture is not auto-imported, so this result is from the production pack files
and cannot be masked by test content.

The first test invocation was stopped before tests ran because the database had
two pending migrations (`20260823010000_create_english_arcade_tables.rb` and
`20260823010100_add_english_arcade_state_machine_fields.rb`). Running the
test-environment migration was the replacement check; the same scoped command
then passed. An earlier exploratory probe also failed when it called
`validation_errors` through a private-method path; that marker is retained as a
failed check, not a corpus error. The duplicate override was removed, the
helper is now exercised through the public API, and both `validate!` and the
redacted `english_arcade:health` payload report zero validation errors.

Historical sibling-corpus snapshot (not evidence for this expansion): 14 chapters, 14 labs, 4 capstones, 16 decision
contrasts, 14 review cards, one curriculum record, 17 linked real-world cases,
44 linked reference records, 334 unique graph links, and 860 legacy Arcade
anchors.
Legacy anchors are `legacy_arcade_item`, never `interview_pack`.
Historical pre-expansion evidence: the latest observed production pack directory contained all eight targets with
12 valid `interview_pack` records and 3 Leitner cards each. The readiness
minimum is 12 items per target with prompt, context, answer, distractors,
feedback and rephrase metadata; `pack_readiness.ready` is true and the adapter
health payload is `ok`. The test fixture remains a contract check, not a source
of production content.
The importer’s explicit `arcade_root:` also gates pack discovery: an isolated
temporary root with no `db/seeds/english_arcade` directory returns zero pack
records even when the Rails application has production packs. This is covered
by the importer fixture test and prevents prose or production records from
crossing test boundaries. A direct probe returned
`interview_pack_count=0, corpus_records=124, links=237, warnings=[]` for such a
temporary root.

## Pending expansion local corpus evidence (2026-08-25)

The current worktree validator, QA and health tasks agree on 1,160 records,
367 links, 14 packs / 176 items / 42 cards, and canonical readiness of 13 packs
/ 164 items / 39 cards. Warnings and validation errors are empty. Two
`ENGLISH_ARCADE_PERSIST=false` imports were byte-identical and each reported
`persisted_documents=0`. This is local pre-review evidence only; the production
deployment still serves the historical release recorded in
`docs/english-c2-arcade-release.md`.

The critical-thinking/runtime handoff adds focused evidence only: content
validator `14/14` packs with `176/42` total items/cards and canonical
`164/39`; controller `27/387`; card + Rails + progress + validator `38/193`;
contract suites `33/1,494`; Ruby syntax and scoped diff check green. No full
suite claim is made. Production remains deployment
`6f07bd3e-30e3-4c76-ae78-cd7f64cd38c7`; the expansion is not committed or
deployed and awaits a fresh independent review.
