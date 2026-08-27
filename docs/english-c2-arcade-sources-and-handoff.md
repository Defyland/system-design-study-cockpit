# English C2 Arcade sources and external handoff

Accessed 2026-08-25. This product is calibrated against CEFR C2 descriptors as
a design reference, not as a certification instrument. It records typed,
self-assessed interview practice only; it does not assess listening, microphone
input, transcription, pronunciation, spontaneous speech, or overall C2.

## Source catalogue

- Council of Europe: [C2 global scale](https://www.coe.int/en/web/common-european-framework-reference-languages/table-1-%20cefr-3.3-common-reference-levels-global-scale), [qualitative spoken-language aspects](https://www.coe.int/en/web/common-european-framework-reference-languages/table-3-cefr-3.3-common-reference-levels-qualitative-aspects-of-spoken-language-use), [Companion Volume](https://rm.coe.int/cefr-companion-volume-with-new-descriptors-2020/16809ea0d4), [descriptors](https://www.coe.int/en/web/common-european-framework-reference-languages/cefr-descriptors), and [mediation](https://www.coe.int/en/web/common-european-framework-reference-languages/mediation).
- Secondary orientation only: [Magoosh proficiency overview](https://magoosh.com/english-speaking/english-proficiency-levels-a-guide-to-determining-your-level/).
- Critical-thinking foundation checked 2026-08-25: Peter A. Facione, *Critical Thinking: A Statement of Expert Consensus for Purposes of Educational Assessment and Instruction — Research Findings and Recommendations* (American Philosophical Association, 1990), [ERIC record](https://eric.ed.gov/?id=ed315423) and [full PDF](https://files.eric.ed.gov/fulltext/ED315423.pdf). The ERIC landing page timed out in this check; the PDF title page and abstract were accessible, so no landing-page metadata is inferred.
- Language reference checked 2026-08-25: Council of Europe, *CEFR Companion Volume and its language versions* (2020), [official page](https://www.coe.int/en/web/common-european-framework-reference-languages/cefr-companion-volume-and-its-language-versions) and [Companion Volume PDF](https://rm.coe.int/cefr-companion-volume-with-new-descriptors-2020/16809ea0d4).
- Incident reasoning checked 2026-08-25: Google SRE, *Troubleshooting Methodology: A Learning Path*, [effective troubleshooting](https://sre.google/sre-book/effective-troubleshooting/), and *Blameless Postmortem for System Resilience*, [postmortem culture](https://sre.google/sre-book/postmortem-culture/). These inform failure probes, evidence boundaries, corrective actions and non-blaming incident updates; they are not a certification rubric.
- Learning method: [retrieval practice](https://pubmed.ncbi.nlm.nih.gov/16507066/), [transfer](https://pubmed.ncbi.nlm.nih.gov/20804289/), and [spacing](https://digitalcommons.usf.edu/psy_facpub/1771/).
- Behavioural interview framing: Oxford Brookes [application guide](https://www.brookes.ac.uk/getmedia/0cbb10a5-eca9-4de2-add7-c62a1695fa51/applications-guide-2023.pdf) defines CARE as Context, Action, Result, Evaluation and distinguishes it from STAR.
- Technical foundations: [Rails Guides](https://guides.rubyonrails.org/), [React effects](https://react.dev/learn/synchronizing-with-effects), [when not to use an effect](https://react.dev/learn/you-might-not-need-an-effect), [Effective Go](https://go.dev/doc/effective_go), [Go diagnostics](https://go.dev/doc/diagnostics), [Elixir processes](https://hexdocs.pm/elixir/main/processes.html), PostgreSQL [current documentation](https://www.postgresql.org/docs/current/), [AWS Well-Architected](https://docs.aws.amazon.com/wellarchitected/latest/userguide/waf.html), and [MIT 6.006](https://ocw.mit.edu/courses/6-006-introduction-to-algorithms-fall-2011/).
- Specific primary references used by the packs: [Ruby syntax and methods](https://docs.ruby-lang.org/en/master/syntax/methods_rdoc.html), [Ruby modules](https://docs.ruby-lang.org/en/master/Module.html), [Elixir Supervisor](https://hexdocs.pm/elixir/Supervisor.html), PostgreSQL [indexes](https://www.postgresql.org/docs/current/indexes.html), [transaction isolation](https://www.postgresql.org/docs/current/transaction-iso.html), [EXPLAIN](https://www.postgresql.org/docs/current/using-explain.html), [explicit locking](https://www.postgresql.org/docs/current/explicit-locking.html), [replication](https://www.postgresql.org/docs/current/high-availability.html), and [partitioning](https://www.postgresql.org/docs/current/ddl-partitioning.html).
- Interview and incident practice: [Microsoft technical interviewing](https://careers.microsoft.com/v2/global/en/hiring-tips/technical-interviewing.html), [Microsoft STAR tips](https://careers.microsoft.com/v2/global/en/hiring-tips/interview-tips.html), and [Microsoft incident response](https://learn.microsoft.com/en-us/azure/well-architected/operational-excellence/incident-response).
- Local method source: the supplied shared GPT thread [Aprendizado DSA e System Design](https://chatgpt.com/share/6a7f0d7a-5874-83e9-8d6d-f638835af195) was the only discoverable GPT thread. A general web crawler exposed only its title; any method details retained in this project come from the local handoff, not an independently verified public transcript. Other private GPT Pro threads were unavailable and no additional share URL was found in the workspace. The retained method specifies closed attempt → Feynman → actionable Black Box → production cards → Leitner → reattempt; Leitner 1/2/4/7/14 and wrong → 1; DSA 45m 5/8/20/8/4 with pattern ≤3m and code ≤20m; System Design 45m 5/5/8/10/10/5/2; mastery 8/10 twice on variants at least 7 days apart. Its audio-recording advice is intentionally excluded by product scope.
- Local content provenance uses clean `../system-design-estudos` paths including `decision-contrasts/01-read-replica-vs-cache-aside.md`, `areas/11-operational-playbooks/playbooks/database-migration-and-backfill.md`, `areas/12-engineering-practice/cards/data-contracts-and-schema-evolution.md`, `areas/06-foundations-distribuidas/topics/consistency-models.md`, `areas/06-foundations-distribuidas/topics/deadlocks.md`, `reviews/day-14-interview-compression.md`, `areas/01-metodo-e-entrevistas/examples/interview-walkthrough-checkout-incident.md`, `areas/05-arquitetura-e-operacao/examples/incident-checkout-degradation.md`, and `areas/11-operational-playbooks/playbooks/incident-severity-and-triage.md`.

## Current-version snapshot (historical check retained)

The following version snapshot was checked against first-party release pages on
2026-08-23 and is retained as historical context; it was not reverified in the
2026-08-25 critical-thinking source pass. These versions inform question
wording and reviewer expectations; they are not claims about the application's
own dependency versions.

- Ruby [4.0.6](https://www.ruby-lang.org/en/news/2026/07/14/ruby-4-0-6-released/) is the current stable Ruby line shown by ruby-lang.org.
- Rails [8.1.3.1](https://www.rubyonrails.org/releases) is the latest listed Rails release.
- React documentation identifies [19.2](https://react.dev/versions) as the latest documented version.
- Go [1.27.0](https://go.dev/doc/devel/release) is the current major stable release; the release page also records supported maintenance lines.
- Elixir [1.20.3](https://elixir.hexdocs.pm/changelog.html) is the current stable changelog release.
- PostgreSQL [18.6](https://www.postgresql.org/about/news/postgresql-186-1711-1615-1519-1424-and-19-beta-3-released-3365/) is the current stable 18 minor release; PostgreSQL 19 is Beta 3 and is not labelled stable in this curriculum.

CEFR C2 is used as a qualitative calibration target: precise reformulation,
consistent grammatical control, appropriate interaction and coherent
discourse. It is not shorthand for “native speaker”, nor can this typed-only
self-assessment validate the CEFR listening, phonology, spontaneous-flow or
interaction descriptors.

## External speaking/listening handoff

The browser never records audio or transcript. An external platform may receive
this minimal, user-initiated payload:

```json
{
  "interface_version": "english-arcade-speaking-handoff-v1",
  "session_id": "opaque-session-id",
  "attempt_id": "opaque-attempt-id",
  "prompt_id": "databases-03-explain-query-plans",
  "target": "databases",
  "task_context": "interviewer follow-up",
  "rubric_axes": ["clarity", "precision", "naturalness", "pragmatic_appropriateness", "technical_correctness"],
  "privacy": "No audio or transcript is accepted, stored, or scored by English Arcade."
}
```

The receiving platform owns consent, recording, transcript retention, and any
speech/listening/pronunciation result. Do not write those results back as an
English Arcade CEFR score.
