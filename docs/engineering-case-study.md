# Engineering Case Study

## Problem

`system-design-estudos` already contains the actual study material, but raw Markdown alone is weak at three things:

- turning reading into repeated retrieval;
- tracking misconceptions and stale topics over time;
- making simulation-driven tradeoffs feel like part of the same study loop.

The cockpit exists to solve those product gaps without taking ownership away from the content repository.

## Why Rails

Rails fits the shape of the problem:

- CRUD over imported study entities and learner state;
- service objects for adaptive sequencing and assessment;
- easy HTML-first surfaces for chapters, drills, and simulations;
- straightforward deployment on Railway for a personal study product.

The app leans on Rails for delivery speed but keeps the important logic in services and explicit models so the technical story is inspectable.

## Main Technical Choices

### Keep content outside the app

The curriculum stays in `system-design-estudos`. The cockpit imports it through filesystem or GitHub sources. This avoids dual authorship and keeps the content repo usable without the app.

### Persist learner signals, not full tutoring state

The app stores attempts, reminders, schedules, missions, and misconceptions. That is enough to drive practice loops without inventing a heavy educational domain model too early.

### Evaluate simulations on the server

Simulation attempts and assessments are backend-owned. This makes the contract testable and keeps the product from trusting the browser for correctness claims.

### Treat side tracks as first-class imported content

Side tracks, backend principles, backend labs, and interview story bank items are imported alongside chapters and cards. This lets the cockpit expose a broader but still coherent study graph.

## Reviewer Fast Path

A technical reviewer can validate the product quickly by reading:

1. `app/services/content/importer.rb`
2. `app/services/adaptive_session_builder.rb`
3. `app/services/simulation_engine.rb`
4. `test/services/content_importer_test.rb`
5. `test/services/adaptive_session_builder_test.rb`
6. `test/services/simulation_engine_test.rb`
7. `test/system/study_flow_test.rb`

That path proves the import boundary, adaptive loop, simulator contract, and user-facing study flow.

## Risks Accepted

- GitHub API sync adds operational dependency for production content import.
- The app is intentionally single-user or low-concurrency in spirit; it does not yet prove broader multi-user scale.
- Basic Auth is enough for a personal learning cockpit but not a general public LMS.
- Learner adaptation is deliberately pragmatic, not model-heavy or AI-first.

## Outcome

The result is a Rails backend asset that demonstrates:

- content-import boundaries;
- explicit service-layer adaptation;
- study-state persistence with useful invariants;
- server-side simulation assessment;
- deployable documentation and personal-product discipline.
