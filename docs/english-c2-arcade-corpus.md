# English C2 Arcade corpus integration

The Arcade is an English-first practice layer over two existing sources:

- `../english-arcade/src/data/seed.ts` (the legacy falling-card game); and
- `../system-design-estudos` (the canonical system-design curriculum).

The cockpit does not replace either source. `Content::EnglishArcadeImporter`
indexes stable IDs, relative source paths, checksums and relationships. It does
not copy the Markdown body or execute the legacy TypeScript. A future content
pack can be supplied as structured hashes (`external_records:`) or as a
machine-readable `config/english_arcade_content.yml` file.

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
distractor, database-name, or other private values.

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

## Observed QA evidence (2026-08-23)

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

The canonical `test/english_arcade/canonical_pack_contract_test.rb` gate now
reports 8/8 production targets present, 12 items and 3 cards each. The
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

Current corpus counts are 14 chapters, 14 labs, 4 capstones, 16 decision
contrasts, 14 review cards, one curriculum record, 17 linked real-world cases,
44 linked reference records, 334 unique graph links, and 860 legacy Arcade
anchors.
Legacy anchors are `legacy_arcade_item`, never `interview_pack`.
The latest observed production pack directory contains all eight targets with
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
