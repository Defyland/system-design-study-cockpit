# frozen_string_literal: true

# Builds the Interview Mode deck from facts in the three resumes supplied by
# the learner. The PDFs stay outside the application: only confirmed claims,
# source filenames, and SHA-256 fingerprints are represented here.
class EnglishArcadeResumeInterviewProfile
  SOURCE_FILES = {
    fullstack: {
      "path" => "allan_flavio_resume_fullstack_v3.pdf",
      "fingerprint" => "4a61afda649bb763c82d9f665bda28c5984f0fd3bf249c66739edc362e681eab"
    },
    smarttv: {
      "path" => "allan_flavio_resume_smarttv.pdf",
      "fingerprint" => "447d298e67d3899723530b0182f7024bbfca611e0900c01c5ed0800fe821618a"
    },
    frontend: {
      "path" => "allan_flavio_resume_frontend.pdf",
      "fingerprint" => "dc2bfbec16dc0c2b926e554defb15703a5ca167ffd569ab67f93e9844c89d67b"
    }
  }.freeze

  CARD_KEYS = %w[
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
  ].freeze

  # These keys deliberately do not reuse the career-pack IDs. The same learner
  # can therefore rehearse a role-specific answer without changing the legacy
  # closed-book career deck or its spaced-repetition history.
  ROLE_METADATA = {
    "frontend" => { label: "Frontend", focus: "UI systems, performance, and platform trade-offs" }.freeze,
    "backend" => { label: "Backend", focus: "APIs, data, reliability, and operations" }.freeze,
    "fullstack" => { label: "Full-stack", focus: "End-to-end decisions and product context" }.freeze,
    "smarttv" => { label: "Smart TV", focus: "Constrained devices, playback, and delivery" }.freeze
  }.freeze
  INTERVIEW_ROLES = ROLE_METADATA.keys.freeze
  PRACTICE_STAGES = %w[produce transfer].freeze
  ROLE_CONTENT_VERSION = "resume-role-interview-2026-09-09-v2"

  ROLE_DECKS = {
    "frontend" => [
      { id: "resume-frontend-01", profile: 0, prompt: "Give a recruiter a concise introduction for a senior frontend role.", context: "Lead with frontend platform ownership, then one measurable delivery result. Do not turn breadth into a technology inventory.", answer: "I’m a frontend engineer who has also worked close to backend and product constraints. I led a migration from a monolithic frontend to eight microfrontends across five squads, reducing deployment time from roughly two days to under one hour. I have also improved a critical list from seven seconds to two seconds under the same data volume through render optimisation and virtualization. I focus on making frontend architecture help teams ship independently while keeping the user-visible path measurable and reliable.", short: "I lead frontend platform work that improves delivery and measurable user performance, including eight microfrontends across five squads and a critical list reduced from seven seconds to two.", deep: "My frontend work combines platform architecture with user-visible performance. I led a Module Federation migration from a monolithic frontend to eight microfrontends across five squads, with deployment time moving from roughly two days to under one hour. On a separate critical list, I kept the data volume constant and used targeted render optimisation and virtualization to reduce load time from seven seconds to two. I would start with the role’s immediate need—delivery autonomy or performance—and then explain the boundary, trade-off, and measured result.", learning: { "answer_structure" => [ "Name your frontend ownership.", "Give one bounded architecture or performance result.", "State the trade-off you managed." ], "useful_phrases" => [ "I led a migration from…", "The measured result was…", "The trade-off was…" ], "pt_help" => "Apresente responsabilidade, resultado mensurável e trade-off. Não liste tecnologias sem conectar ao impacto." } },
      { id: "resume-frontend-02", profile: 2, answer: "I led a migration from a monolithic frontend to eight microfrontends across five squads using Module Federation. The practical goal was independent delivery, and deployment time moved from roughly two days to under one hour. The benefit was team autonomy, with a larger coordination surface for shared contracts, integration, and consistency. I would choose that structure only when team boundaries and release independence justify the operational overhead.", short: "I led eight microfrontends across five squads, moving deployment time from roughly two days to under one hour while keeping shared contracts explicit.", deep: "I led the migration from a monolithic frontend to eight microfrontends across five squads using Module Federation. Deployment time moved from roughly two days to under one hour, enabling more independent releases. I would frame the decision around team and deployment boundaries: autonomy was the advantage, while integration, shared dependencies, consistency, and observability became explicit coordination costs. If independent ownership does not repay those costs, I would prefer a modular monolith." },
      { id: "resume-frontend-03", profile: 7 }
    ],
    "backend" => [
      { id: "resume-backend-01", profile: 0, prompt: "Give a concise introduction for a senior backend role.", context: "Connect production scale, reliability responsibility, and one concrete system boundary. Keep implementation details inside the resume evidence.", answer: "I’m a backend engineer with experience in Rails and Go systems where reliability, payment correctness, and delivery speed were product concerns. I worked on Rails APIs handling more than 100 million requests per day, with targeted API and query optimisation, and on Go Pix settlement services with idempotent message processing. I like making failure boundaries explicit—what can retry, what must remain idempotent, and which signal verifies the change—before choosing a mechanism.", short: "I build Rails and Go services with explicit reliability and payment boundaries, including Rails APIs above 100 million requests per day and retry-safe Pix processing.", deep: "My backend profile is centred on reliable state changes under real workload. I have worked on Rails APIs handling more than 100 million requests per day, with API and query optimisation, incident response, and test coverage, and on Go Pix settlement services using transactional outbox and idempotent inbox patterns. In an interview I would choose one system boundary, explain the failure mode it contained, then name the observable result rather than claiming that a single tool solved reliability.", learning: { "answer_structure" => [ "Name the system responsibility.", "Choose one reliability or payment boundary.", "Name the verification signal or outcome." ], "useful_phrases" => [ "I treated retries as part of the contract.", "The boundary I owned was…", "I would verify it through…" ], "pt_help" => "Use 'reliability' como responsabilidade de produto: explique o limite de falha e como você verificaria o resultado." } },
      { id: "resume-backend-02", profile: 1, answer: "At that scale, I treated latency, incidents, and data correctness as product responsibilities rather than cleanup work. I worked on Rails APIs handling more than 100 million requests per day, with targeted API and query optimisation, incident response, and strong automated test coverage on a platform designed for Brazilian Central Bank requirements. I would explain the specific signal I owned—latency, query behaviour, incident response, or regression protection—and clarify the exact service boundary before going deeper.", short: "At more than 100 million Rails API requests per day, I treated latency, query behaviour, incident response, and regression protection as product responsibilities.", deep: "The scale made reliability an everyday constraint. I worked on Rails APIs handling more than 100 million requests per day, with targeted API and query tuning, incident response, and about 95% RSpec coverage on a platform designed for Brazilian Central Bank requirements. I would describe the observed performance or correctness problem, the bounded change I owned, and the verification signal. I would not invent a database plan or incident mechanism without tying it to the project example." },
      { id: "resume-backend-03", profile: 5 }
    ],
    "fullstack" => [
      { id: "resume-fullstack-01", profile: 0, prompt: "Give a concise introduction for a senior full-stack role.", context: "Connect one backend scale example, one frontend delivery example, and the engineering thread between them.", answer: "I’m a full-stack engineer with more than ten years across Rails, Go, React, React Native, and TypeScript. On the backend, I worked on Rails APIs handling more than 100 million requests per day and payment and Pix reliability boundaries. On the frontend, I led eight microfrontends across five squads and improved a critical list from seven seconds to two under the same data volume. The thread is translating product needs into dependable delivery across the API, interface, and operational boundary.", short: "I’m a full-stack engineer across Rails and Go services, including APIs above 100 million daily requests and eight microfrontends across five squads.", deep: "I work across the product boundary when it helps a team make a coherent decision. My backend experience includes Rails APIs above 100 million requests per day and retry-safe payment and Pix processing. My frontend experience includes a migration to eight microfrontends across five squads and a measured list-load improvement from seven seconds to two. I do not present that range as universal expertise; I use it to connect API, interface, release, and reliability trade-offs when a role needs that view.", learning: { "answer_structure" => [ "State your full-stack through-line.", "Give one backend and one frontend evidence point.", "Connect them to a product outcome." ], "useful_phrases" => [ "The thread connecting the work is…", "On the backend…", "On the frontend…" ], "pt_help" => "Conecte backend e frontend por uma decisão de produto; evite apenas enumerar linguagens e frameworks." } },
      { id: "resume-fullstack-02", profile: 4 },
      { id: "resume-fullstack-03", profile: 9 }
    ],
    "smarttv" => [
      { id: "resume-smarttv-01", profile: 0, prompt: "Give a concise introduction for a Smart TV engineering role.", context: "Start with television constraints and product surface, then name a platform or performance result from the resume.", answer: "I build television experiences where remote navigation, constrained hardware, content scale, and playback behaviour all shape the architecture. I shipped one React Native codebase through ReNative to Samsung Tizen and LG webOS, covering Live, VOD, catch-up, Bitmovin, and multi-DRM. I also measured the channel-change path; after moving EPG pagination to the server side, that scenario improved by roughly one third. I treat shared code as a starting point, while keeping device-specific performance and playback boundaries explicit.", short: "I ship Smart TV products for Tizen and webOS, balancing shared code with explicit remote, performance, EPG, playback, and DRM constraints.", deep: "My Smart TV experience is product and platform work together. I shipped a shared React Native/ReNative application to Samsung Tizen and LG webOS for Live, VOD, and catch-up, with Bitmovin and multi-DRM. On performance, I used the Performance API to baseline channel changes and saw roughly a one-third reduction after server-side EPG pagination. I would start with the device constraint, explain the bounded change, and avoid implying that a shared framework removes platform-specific work.", learning: { "answer_structure" => [ "Name the television constraint.", "Describe the platform or playback scope.", "Give one measured, bounded improvement." ], "useful_phrases" => [ "The device constraint was…", "I kept platform-specific behaviour explicit.", "The measured scenario improved by…" ], "pt_help" => "Em Smart TV, destaque navegação por controle remoto, hardware limitado, EPG e playback antes de falar de UI genérica." } },
      { id: "resume-smarttv-02", profile: 10 },
      { id: "resume-smarttv-03", profile: 3, answer: "On Samsung Tizen and LG webOS, memory and CPU constraints meant I used the Performance API to establish a channel-change baseline instead of optimising by feel. After moving EPG pagination to the server side, the measured scenario improved by roughly one third. I would present that as an observed result of the bounded change, then explain the broader lesson: instrument the user-visible path first and move work away from constrained hardware when the measurement supports it.", short: "I measured Smart TV channel-change time with the Performance API and saw roughly a one-third reduction after server-side EPG pagination in the measured scenario.", deep: "Samsung Tizen and LG webOS made memory and CPU limits part of the design. I used the Performance API to baseline the channel-change path, then moved EPG pagination to the server side; the measured scenario improved by roughly one third. I would explain the device constraint, measurement, bounded change, and observed result in that order. Bitmovin and multi-DRM are relevant platform experience, but I would not claim they caused this particular improvement." }
    ]
  }.freeze

  # Private scoring anchors for the role rehearsal only. They are sourced from
  # the same bounded claims as the response, support ordinary paraphrases, and
  # deliberately do not attempt to judge grammar, fluency, or semantic truth.
  CARD_RECALL_CHECKS = {
    "resume-frontend-01" => [ [ "frontend platform", "frontend engineer" ], [ "eight microfrontends", "8 microfrontends" ], [ "seven seconds to two", "7 seconds to 2" ] ],
    "resume-frontend-02" => [ [ "eight microfrontends", "8 microfrontends" ], [ "five squads", "5 squads" ], [ "under one hour", "less than one hour" ] ],
    "resume-frontend-03" => [ [ "critical list", "list component" ], [ "seven seconds", "7 seconds" ], [ "two seconds", "2 seconds" ] ],
    "resume-backend-01" => [ [ "rails and go", "go and rails" ], [ "100 million requests", "100m requests" ], [ "pix", "payment" ] ],
    "resume-backend-02" => [ [ "rails apis", "rails api" ], [ "100 million requests", "100m requests" ], [ "query", "incident" ] ],
    "resume-backend-03" => [ [ "apache kafka", "kafka" ], [ "four critical services", "4 critical services" ], [ "asynchronous", "event-driven" ] ],
    "resume-fullstack-01" => [ [ "full-stack engineer", "fullstack engineer" ], [ "100 million requests", "100m requests" ], [ "eight microfrontends", "8 microfrontends" ] ],
    "resume-fullstack-02" => [ [ "idempotent", "idempotency" ], [ "payment", "pix" ], [ "transactional outbox", "idempotent inbox" ] ],
    "resume-fullstack-03" => [ [ "eight engineers", "8 engineers" ], [ "code reviews", "technical interviews" ], [ "knowledge sharing", "mentored" ] ],
    "resume-smarttv-01" => [ [ "samsung tizen", "tizen" ], [ "lg webos", "webos" ], [ "epg pagination", "server side epg" ] ],
    "resume-smarttv-02" => [ [ "samsung tizen", "tizen" ], [ "lg webos", "webos" ], [ "bitmovin", "multi-drm" ] ],
    "resume-smarttv-03" => [ [ "performance api", "performance" ], [ "epg pagination", "server-side epg" ], [ "one third", "one-third" ] ]
  }.freeze

  # Decision details and proposed checks use conditional language: the resume
  # confirms the project facts, not every explanation a learner might rehearse.
  CARD_REASONING_QUESTIONS = {
    "resume-frontend-01" => [
      { "question" => "Why would I lead with platform ownership in my introduction?", "answer" => "I would lead with platform ownership because it connects my frontend work to how teams deliver. I led eight microfrontends across five squads, so I can anchor that introduction in a concrete scope before explaining the architecture." },
      { "question" => "Which benefit would I connect to that ownership?", "answer" => "I would connect independent delivery to deployment time moving from roughly two days to under one hour. I would then use my separate seven-to-two-second critical-list result to show that I also care about the experience people actually use." },
      { "question" => "What would I leave out, and when would I change my emphasis?", "answer" => "I would avoid explaining both projects in depth at once because that costs clarity in a short introduction. If the role mainly needs UI performance, I would lead with the critical list and leave the microfrontend story for a follow-up." },
      { "question" => "How would I support the claims when the interviewer goes deeper?", "answer" => "I would separate my release metric from my list metric and explain the boundary of each. I would keep the list comparison at the same data volume and verify any additional measurement detail before claiming it as part of my experience." }
    ],
    "resume-frontend-02" => [
      { "question" => "Why would I choose Module Federation for this kind of migration?", "answer" => "I would choose it when independent squad ownership needs independent releases, because a single deployment can couple otherwise separate work. My concrete example is the migration I led to eight microfrontends across five squads using Module Federation." },
      { "question" => "What advantage would I expect from those boundaries?", "answer" => "I would expect squads to release their owned areas with less waiting on a shared release. In my example, deployment time moved from roughly two days to under one hour; I would use that reported outcome to explain the value of autonomy." },
      { "question" => "What would make a modular monolith a better choice for me?", "answer" => "I would prefer a modular monolith if teams do not need separate release cycles, because microfrontends add shared-dependency, integration, and observability work. I would accept that coordination cost only when independent ownership and delivery repay it." },
      { "question" => "How would I verify that the split helps delivery?", "answer" => "I would compare deployment time at the same release boundary and check whether squads can actually deliver their owned changes independently. I would also check integration failures and shared-contract changes, because a faster deployment is less useful if I move the waiting or breakage elsewhere." }
    ],
    "resume-frontend-03" => [
      { "question" => "Why would I use virtualization for a critical list?", "answer" => "I would use virtualization when profiling shows that rendering list items beyond the visible area adds unnecessary work. In my critical-list example, I applied targeted render optimisation and virtualization under the same data volume, reducing load time from seven seconds to two seconds." },
      { "question" => "What benefit would I connect to the rendering change?", "answer" => "I would explain that I can reduce rendering work while preserving the data volume in the comparison. I would connect the benefit to the measured critical list load, because that is the user-visible path my seven-to-two-second result describes." },
      { "question" => "What costs and alternatives would I consider?", "answer" => "I would check whether virtualization complicates focus, scrolling, or item sizing in this list. For a small list I would prefer simpler rendering; if measurement points to data retrieval instead, I would investigate that boundary before choosing a rendering technique." },
      { "question" => "How would I verify that the improvement is real?", "answer" => "I would repeat the critical list measurement with the same data volume and comparable conditions. I would check interaction responsiveness and memory separately, because I cannot use one faster load time to prove every part of the interface improved." }
    ],
    "resume-backend-01" => [
      { "question" => "Why would I introduce myself through reliability boundaries?", "answer" => "I would start with reliability because it connects my Rails and Go experience to a product consequence: a state change must remain correct when work retries. I can ground that introduction in Rails APIs above 100 million requests per day and my Go Pix settlement work." },
      { "question" => "What advantage does that give my backend story?", "answer" => "I would make the responsibility concrete before naming a framework: I would explain what may retry, what must stay idempotent, and what result needs verification. That gives me a coherent way to connect high-volume API work with payment correctness." },
      { "question" => "What is the cost of that emphasis, and when would I change it?", "answer" => "I would risk sounding too payment-specific if I spent the whole introduction on Pix. For a role focused on API performance, I would lead with my Rails API and query optimisation work and keep the payment boundary as a second example." },
      { "question" => "How would I make the reliability claim verifiable?", "answer" => "I would choose one service boundary and name the relevant check, such as a latency comparison or a duplicate-message test. I would distinguish those proposed checks from results I can support from my experience; request volume alone would not verify correctness for me." }
    ],
    "resume-backend-02" => [
      { "question" => "Why would I start with targeted API and query work at this scale?", "answer" => "I would start by locating the expensive API or query path because daily traffic alone does not tell me what to change. I worked on Rails APIs above 100 million requests per day with targeted API and query optimisation, so I would use that bounded responsibility as my starting point." },
      { "question" => "What benefit would I seek from a bounded change?", "answer" => "I would aim to reduce work on the affected request path while keeping data correctness visible. I would connect latency, query behaviour, incident response, and regression protection to the product, because I need more than a high traffic number to explain the value of my work." },
      { "question" => "What trade-off would I weigh against a larger redesign?", "answer" => "I would weigh the limited reach of a local optimisation against the migration and operational cost of a redesign. I would consider changing the larger boundary if measurement showed that targeted changes could not address the actual constraint; I would verify the database details before describing a specific historical fix." },
      { "question" => "How would I verify performance without overlooking correctness?", "answer" => "I would compare the affected API latency and query behaviour under comparable workload, then check the state and failure paths the change touches. I would use automated tests as regression evidence and incident signals as operational evidence; I would not treat my coverage figure as proof that failures cannot occur." }
    ],
    "resume-backend-03" => [
      { "question" => "Why would I use Kafka across these service boundaries?", "answer" => "I would use asynchronous events when downstream work can progress independently, because a chain of direct calls makes one service wait on another. My example is introducing Apache Kafka to eliminate synchronous bottlenecks across four critical services." },
      { "question" => "What advantage would I connect to asynchronous communication?", "answer" => "I would connect it to reducing direct coupling on the critical workflow so services can process work independently. I would explain that independence as the benefit of my four-service change without inventing a latency or throughput result." },
      { "question" => "What costs would make me keep a synchronous call?", "answer" => "I would account for message contracts, duplicate handling, retries, observability, and consumer recovery. If my caller needs an immediate bounded result, I would keep a synchronous call because waiting for an eventual event would not satisfy that response requirement." },
      { "question" => "How would I check that decoupling improved the workflow?", "answer" => "I would measure completion of the affected workflow and inspect consumer lag and failed-message recovery. I would also test duplicates and a consumer interruption, because publishing an event successfully would not tell me that the intended business work finished correctly." }
    ],
    "resume-fullstack-01" => [
      { "question" => "Why would I connect backend and frontend in one introduction?", "answer" => "I would connect them through product delivery because my full-stack value is in understanding decisions across the API and interface. I can support that with Rails APIs above 100 million requests per day and my migration to eight microfrontends across five squads." },
      { "question" => "What advantage would that broader view give my explanation?", "answer" => "I would use it to identify which layer owns the constraint before proposing a change. I can contrast my payment reliability work with my critical-list improvement from seven seconds to two, showing why I would investigate state correctness and rendering performance differently." },
      { "question" => "What is the cost of breadth, and when would I narrow the story?", "answer" => "I would lose depth if I turned the answer into a list of stacks and metrics. For a backend-heavy role I would focus on Rails and Go reliability; for a frontend-heavy role I would choose delivery boundaries or the critical list, keeping the other layer as supporting context." },
      { "question" => "How would I verify an end-to-end claim?", "answer" => "I would trace the specific user or business outcome across the interface and API, then check each relevant boundary. I would keep my separate project metrics separate: a faster list would not verify payment correctness, and backend request volume would not prove frontend responsiveness." }
    ],
    "resume-fullstack-02" => [
      { "question" => "Why would I design payment processing around idempotency?", "answer" => "I would assume retries and partial failure because a payment request can be repeated even when the earlier outcome is unclear. I built idempotent and auditable Rails payment state transitions and used transactional outbox and idempotent inbox patterns in Go Pix settlement services." },
      { "question" => "What benefit would I connect to outbox, inbox, and recovery?", "answer" => "I would use the outbox to preserve the intent to publish alongside the local state change and the idempotent inbox to protect the consumer from repeated processing. I would connect dead-letter handling and auditable records to a recoverable payment path, keeping my explanation focused on the business transition." },
      { "question" => "What cost would I accept, and what simpler option would I consider?", "answer" => "I would accept stored message state, retry policies, and recovery work when the payment boundary crosses asynchronous services. For work entirely inside one database I would first consider a local transaction with idempotent state changes; I would not assume that transaction also covers an external provider." },
      { "question" => "How would I verify that retries cannot duplicate a charge?", "answer" => "I would replay the same payment message and test an interruption around the state-change and publication boundary, checking the resulting business state and audit trail. I would also exercise dead-letter recovery, because I need to know how failed work completes safely as well as how duplicates are handled." }
    ],
    "resume-fullstack-03" => [
      { "question" => "Why would I lead through reviews and knowledge sharing?", "answer" => "I would use reviews and knowledge sharing because I want engineers to understand a decision well enough to apply it independently. I led eight engineers through code reviews, technical interviews, and structured knowledge sharing, and earlier mentored three developers while strengthening testing practices." },
      { "question" => "What advantage would I seek for the team?", "answer" => "I would aim to make technical reasoning and quality standards repeatable so delivery does not depend on one person's availability. I would use a concrete review or testing discussion to connect the implementation choice to its production consequence." },
      { "question" => "What costs would make me change the collaboration format?", "answer" => "I would watch for review queues and repeated meetings consuming delivery time. For a small reversible decision I would let the responsible engineer proceed within clear boundaries; for a risky or disputed change I would use a focused discussion with evidence instead of adding a broad meeting by default." },
      { "question" => "How would I check whether my leadership approach helps?", "answer" => "I would look for engineers applying the reasoning independently, recurring review issues decreasing, and delivery retaining its quality. I would inspect those signals directly instead of using my code volume or a test coverage percentage as a substitute for team capability." }
    ],
    "resume-smarttv-01" => [
      { "question" => "Why would I open with television constraints?", "answer" => "I would start with remote navigation, constrained hardware, and playback because those constraints explain the engineering choices in my Smart TV work. I shipped a React Native/ReNative codebase to Samsung Tizen and LG webOS, so I can connect the introduction to actual platforms." },
      { "question" => "Which benefit would I highlight from shared code?", "answer" => "I would highlight sharing stable product flows across Live, VOD, and catch-up to reduce duplication. I would pair that with my measured channel-change improvement after server-side EPG pagination, showing how I connect platform delivery to a user-visible result." },
      { "question" => "What cost would I acknowledge, and when would I change the approach?", "answer" => "I would acknowledge that shared code still needs device-specific navigation, performance, and playback work. If a platform capability diverged, I would isolate that part behind an explicit boundary; I would consider a separate implementation only when maintaining the shared path cost more than it saved." },
      { "question" => "How would I substantiate the introduction on real devices?", "answer" => "I would verify navigation and playback on the target Tizen and webOS devices and measure the relevant user-visible path. I would keep my roughly one-third channel-change result tied to its measured scenario, because I cannot infer complete device parity from a shared codebase." }
    ],
    "resume-smarttv-02" => [
      { "question" => "Why would I keep playback and device capabilities explicit?", "answer" => "I would keep them explicit because sharing React Native product code does not make Tizen and webOS capabilities identical. I shipped through ReNative and integrated Bitmovin for Live, VOD, and catch-up with multi-DRM, so I would explain the player as one part of the platform boundary." },
      { "question" => "What benefit would I seek from sharing stable product flows?", "answer" => "I would share stable flows to avoid duplicating common product behaviour while retaining control over device adaptations. I would keep remote focus, memory, rendering, EPG, and playback decisions visible so that I can address a platform constraint without reshaping every shared flow." },
      { "question" => "What are the costs, and when would I use a platform-specific path?", "answer" => "I would account for capability checks, adaptation code, and a larger device test surface. If a shared playback or navigation abstraction hid a real device difference, I would introduce a focused platform-specific path rather than forcing the same behaviour or duplicating the entire application." },
      { "question" => "How would I verify the playback boundary?", "answer" => "I would check supported content modes and DRM behaviour on the target devices, including channel changes, audio or subtitle switching, and recovery under relevant network conditions. I would test remote focus and resource behaviour alongside playback, because a working player alone would not prove the television experience works." }
    ],
    "resume-smarttv-03" => [
      { "question" => "Why would I measure channel changes before changing EPG work?", "answer" => "I would measure the user-visible path first because memory and CPU constraints alone do not identify the work that needs changing. I used the Performance API to establish a channel-change baseline on Samsung Tizen and LG webOS before the server-side EPG pagination change." },
      { "question" => "What benefit would I connect to server-side pagination?", "answer" => "I would use server-side pagination to reduce the amount of EPG work the constrained device needs to handle. In my measured channel-change scenario, I saw roughly a one-third reduction after that change, and I would keep the result tied to that path." },
      { "question" => "What costs and alternatives would I consider?", "answer" => "I would account for server requests, loading states, and network dependence when moving pagination away from the device. If a small EPG already performed well locally, I would keep the simpler client path; if rendering dominated the measurement, I would investigate that work before moving more logic to the server." },
      { "question" => "How would I verify a later change or a device-specific regression?", "answer" => "I would repeat the channel-change measurement on the affected model under comparable content and network conditions, then compare it with the baseline. I would check EPG correctness as well as timing, and I would avoid extending my one-third result to unmeasured devices or attributing it to Bitmovin." }
    ]
  }.freeze

  CARD_VARIANT_CONTENT = {
    "resume-frontend-01" => { follow_up: [ "What made the microfrontend boundary useful rather than just more complicated?", "I would explain the boundary through the release need of five squads: in my example, deployment time moved from roughly two days to under one hour. I would weigh that reported outcome against shared contracts and integration discipline, because independent releases still need coordination.", [ "Each squad chose unrelated standards, so integration no longer needed ownership.", "Module Federation alone made every frontend change faster." ] ], delayed_variant: [ "If the next team is smaller, would you repeat that migration?", "I would first test whether independent ownership and release cadence repay the integration cost. For a smaller team, a well-modularised application can preserve clarity with less operational overhead than eight deployable frontends.", [ "Yes, because smaller repositories are always easier to maintain.", "Yes, because microfrontends eliminate shared dependency work." ] ] },
    "resume-frontend-02" => { follow_up: [ "How did you keep eight microfrontends from becoming eight incompatible products?", "I would keep shared dependencies, integration, and consistency explicit because independent releases still need compatible contracts. I would describe autonomy as the result, while making the coordination surface visible rather than presenting each squad as fully isolated.", [ "I let every squad select any runtime contract so delivery stayed fast.", "After the split, shared standards were no longer necessary." ] ], delayed_variant: [ "What would make you stop a microfrontend migration before completing it?", "I would stop if the organisational boundary or release need did not justify the extra integration and observability cost. The architecture should follow independent ownership, not serve as a default modernization step.", [ "I would continue because the migration already proves the target architecture is correct.", "I would decide only from the number of repositories created." ] ] },
    "resume-frontend-03" => { follow_up: [ "How did you establish that the list improvement was meaningful?", "I kept the data volume constant, measured the critical list path, and then applied targeted render optimisation and virtualization. The comparison stayed useful because the workload did not become smaller just to improve the number.", [ "I returned fewer records, which made the list appear faster.", "I assumed virtualization was sufficient without measuring the critical path." ] ], delayed_variant: [ "A later release feels slower. Where would you begin?", "I would remeasure the same user-visible list path under the same data volume, then inspect rendering work before changing the architecture. That keeps a regression investigation comparable to the original seven-to-two-second result.", [ "I would claim the original metric guarantees every interaction is still fast.", "I would remove detail from the UI before checking the workload." ] ] },
    "resume-backend-01" => { follow_up: [ "Which backend boundary would you explain first in a payments interview?", "I would start with the state transition that must not duplicate, then explain retries, idempotency, and the signal used to verify the result. That makes the reliability decision concrete before naming Rails, Go, or a queue.", [ "I would start by listing every backend technology I have used.", "I would say retries are rare enough to handle manually." ] ], delayed_variant: [ "How would you adapt that introduction for a Go-focused team?", "I would keep the same reliability through-line and lead with the Pix settlement work: transactional outbox, idempotent inbox, and dead-letter handling for retried payment messages. I would still keep the claim tied to that payment boundary.", [ "I would claim all Rails experience transfers unchanged to every Go service.", "I would omit the payment boundary and focus only on language syntax." ] ] },
    "resume-backend-02" => { follow_up: [ "Which signal would tell you a reliability change helped at 100M daily requests?", "I would name the bounded signal for the change—latency, query behaviour, incident response, or regression protection—and the service boundary it belongs to. High traffic provides context, but it does not make one metric explain the whole system.", [ "I would use request volume alone as proof that the change worked.", "I would promise every request became fast and error-free." ] ], delayed_variant: [ "What would you say when asked for an incident detail you cannot support from memory?", "I would keep the supported responsibility clear, say that I would need to verify the exact incident detail, and offer the closest documented example. Adding a likely database or incident mechanism would make the story less trustworthy.", [ "I would fill in a plausible incident narrative to keep the answer fluent.", "I would generalise the latency result to every service." ] ] },
    "resume-backend-03" => { follow_up: [ "What new operational work came with Kafka across four services?", "I introduced Kafka across four critical services to address synchronous bottlenecks. I would explain the accompanying responsibilities for message contracts, duplicate handling, retries, observability, and consumer recovery, and use asynchronous communication selectively where the workflow can progress independently.", [ "Kafka guarantees consumers never need duplicate protection.", "After Kafka, direct calls are inappropriate for every request." ] ], delayed_variant: [ "When would you keep a synchronous call instead?", "I would keep it where the caller needs an immediate, bounded result. The event-driven path is useful when decoupling improves the critical workflow; it is not a substitute for an explicit response requirement.", [ "I would replace every call with events because they are always more scalable.", "I would choose based only on whether Kafka is already installed." ] ] },
    "resume-fullstack-01" => { follow_up: [ "How do you decide whether to go deep on the API or the interface in a full-stack interview?", "I start from the product failure or delivery constraint, then choose the layer that owns it. For example, payment retries belong to a state boundary, while list load time belongs to rendering work under the same data volume.", [ "I would always start with the frontend because it is visible to users.", "I would list both stacks without connecting either to an outcome." ] ], delayed_variant: [ "This role is backend-heavy. Which part of your story changes?", "I would lead with the Rails and Go reliability work—high-volume APIs, payment idempotency, and Pix message handling—then mention frontend experience only where it clarifies an end-to-end decision.", [ "I would repeat the same broad introduction regardless of the role.", "I would claim frontend metrics prove backend correctness." ] ] },
    "resume-fullstack-02" => { follow_up: [ "How would you explain protection against a duplicated payment message?", "I would describe the business transition first, then the idempotent state boundary and recovery trail. In the Pix work, transactional outbox, idempotent inbox, and dead-letter queues made retried messages safe to process.", [ "I would rely on a single local transaction with the external provider.", "I would limit retries instead of making the operation idempotent." ] ], delayed_variant: [ "What does tokenization leave unresolved?", "I would use tokenization to address the payment-data boundary while keeping release safety, idempotent processing, and operational recovery explicit. I would verify those responsibilities separately because tokenization alone cannot guarantee them.", [ "Tokenization makes payment reliability and deployment controls unnecessary.", "Tokenization proves every transaction completes faster." ] ] },
    "resume-fullstack-03" => { follow_up: [ "How did you keep leadership technical while leading eight engineers?", "I used reviews, technical interviews, and structured knowledge sharing while staying accountable for architecture, reliability, and delivery. The aim was to make decision boundaries and quality standards repeatable rather than centralising every decision in one person.", [ "I made every architectural decision so the team could avoid debate.", "I measured leadership mainly through my individual code volume." ] ], delayed_variant: [ "What would you do when a review disagreement blocks delivery?", "I would make the constraint and production outcome explicit, ask for evidence for the competing options, and record the decision boundary so the team can apply it again. That turns a local disagreement into shared capability.", [ "I would end the discussion by choosing the option I personally prefer.", "I would defer quality entirely to CI so delivery can continue." ] ] },
    "resume-smarttv-01" => { follow_up: [ "What did the shared Tizen and webOS codebase still need to keep separate?", "I shipped shared product flows through one codebase, and I would keep remote focus navigation, memory and CPU behaviour, rendering throughput, playback, and device capabilities at explicit platform boundaries because the devices differ. I would explain shared code as a way to reduce duplication while still accounting for platform differences.", [ "ReNative removed the need for device-specific performance work.", "Large television screens made responsive styling the only important constraint." ] ], delayed_variant: [ "A new device behaves differently from the shared implementation. What is your first move?", "I would isolate the device-specific capability or performance boundary, measure the user-visible path, and avoid changing common product logic until the constraint is clear. That preserves the value of shared code without hiding the platform difference.", [ "I would force the device to follow the shared path without measurement.", "I would duplicate the entire application for the new device immediately." ] ] },
    "resume-smarttv-02" => { follow_up: [ "Why did player and DRM experience not remove the Smart TV engineering problem?", "I can discuss using Bitmovin and multi-DRM for Live, VOD, and catch-up, while still accounting for remote navigation, hardware limits, EPG scale, and network behaviour. I would explain the player as one boundary within the broader television experience.", [ "Bitmovin made channel changes and DRM behaviour universal across platforms.", "Multi-DRM removed the need to test device-specific playback." ] ], delayed_variant: [ "How would you frame playback risk for an interviewer?", "I would name the content mode and platform constraint, then explain the observable behaviour to protect—such as channel changes, audio or subtitle switching, or recovery under network conditions. I would not claim one player abstraction guarantees parity.", [ "I would say the player vendor owns all playback risk.", "I would discuss only visual styling because playback is infrastructure." ] ] },
    "resume-smarttv-03" => { follow_up: [ "Why move EPG pagination server-side after measuring channel changes?", "I used the Performance API to baseline the user-visible channel-change path on constrained television hardware. After moving EPG pagination server-side, I saw roughly a one-third improvement in that scenario; I would explain the reduced device work while keeping the causal claim limited to the measured path.", [ "I would say server-side pagination makes every television model consistently fast.", "I would attribute the improvement to Bitmovin without evidence." ] ], delayed_variant: [ "How would you investigate a regression on only one television model?", "I would reproduce and measure the channel-change path on that model, compare the device constraint with the prior baseline, and then decide whether the EPG or rendering boundary changed. A prior one-third result is a reference, not a universal guarantee.", [ "I would assume the original result rules out a device-specific regression.", "I would remove animations before measuring the channel-change path." ] ] }
  }.freeze

  INTRO_CARD_IDS = %w[
    resume-frontend-01 resume-backend-01 resume-fullstack-01 resume-smarttv-01
  ].freeze

  INTRO_EVIDENCE = {
    "frontend" => {
      sources: %i[frontend smarttv],
      verified: [ "Led a migration to eight microfrontends across five squads.", "Deployment time moved from roughly two days to under one hour.", "Reduced a critical list from seven seconds to two seconds under the same data volume." ],
      distractors: [ [ "I can use any frontend architecture because I know many frameworks.", "breadth without evidence", "The introduction needs a responsibility and bounded result." ], [ "Microfrontends and virtualization made every frontend problem disappear.", "universal mechanism", "Both decisions carried explicit trade-offs and bounded outcomes." ] ]
    },
    "backend" => {
      sources: %i[fullstack],
      verified: [ "Owned Rails APIs handling more than 100 million daily requests.", "Built Go Pix settlement services with transactional outbox and idempotent inbox.", "Used targeted API and query optimisation with incident-response accountability." ],
      distractors: [ [ "At high traffic, adding servers is the only reliability decision that matters.", "single mechanism", "Reliability also required explicit state and recovery boundaries." ], [ "I can guarantee every request is fast and error-free.", "absolute guarantee", "The evidence supports bounded engineering responsibility, not an absolute outcome." ] ]
    },
    "fullstack" => {
      sources: %i[fullstack frontend smarttv],
      verified: [ "Rails APIs handled more than 100 million daily requests.", "Built retry-safe payment and Pix processing boundaries.", "Led eight microfrontends across five squads.", "Reduced a critical list from seven seconds to two seconds under the same data volume." ],
      distractors: [ [ "I can solve every product problem because I work across the stack.", "universal capability", "Range needs to remain tied to a specific product boundary." ], [ "Frontend and backend work are separate, so their trade-offs should never inform each other.", "false separation", "The introduction explains how the roles connect through delivery outcomes." ] ]
    },
    "smarttv" => {
      sources: %i[smarttv fullstack],
      verified: [ "Shipped one ReNative codebase to Samsung Tizen and LG webOS.", "The product covered Live, VOD, catch-up, Bitmovin, and multi-DRM.", "Performance API measurement and server-side EPG pagination improved the channel-change scenario by roughly one third." ],
      distractors: [ [ "A shared codebase removes television-specific navigation and performance work.", "false parity", "Shared code still needed explicit device boundaries." ], [ "The player vendor guarantees consistent playback behaviour on every device.", "vendor guarantee", "Playback and device behaviour remained an engineering responsibility." ] ]
    }
  }.freeze

  PROFILES = [
    {
      prompt: "Give me a concise introduction that connects your backend scale, frontend leadership, and Smart TV work.",
      context: "Use a first-person through-line, not a technology inventory. Keep every metric tied to the resume evidence.",
      answer: "I’m a full-stack engineer with more than ten years of experience across Rails, Go, React, React Native, and TypeScript. My recent backend work includes Rails APIs handling more than 100 million requests per day and a platform designed for Brazilian Central Bank requirements. I’ve also led frontend platform changes across eight microfrontends and five squads, and I’ve delivered Smart TV applications for Samsung Tizen and LG webOS. The thread connecting those roles is reliable delivery on constrained or high-scale systems, with enough product context to explain the trade-offs clearly.",
      short: "I’m a full-stack engineer with more than ten years of experience across high-scale Rails systems, frontend platforms, and Smart TV products. I focus on reliable delivery and on making technical trade-offs clear to the team.",
      deep: "I’m a full-stack engineer with more than ten years of experience across Rails, Go, React, React Native, and TypeScript. On the backend, my resume documents Rails APIs handling more than 100 million requests per day, a platform designed around Brazilian Central Bank requirements, and Go services for Pix settlement. On the frontend, I led a move to eight microfrontends across five squads and worked on a TurboRepo spanning fifteen applications. I have also delivered Samsung Tizen and LG webOS applications with Bitmovin and multi-DRM playback. I would use the part most relevant to the role as the starting point, then go deeper on responsibility, constraints, and measurable outcomes.",
      distractors: [
        [ "I’ve used many technologies across backend, frontend, mobile, and television products, so I can adapt to almost any engineering problem.", "breadth without evidence", "It lists range but gives the interviewer no verified scale, decision, or through-line to probe." ],
        [ "I’m primarily a Rails engineer, and the frontend and Smart TV work are secondary details that are not important to my current profile.", "false narrowing", "It discards relevant leadership and constrained-device evidence that is present in the resumes." ],
        [ "I have worked on extremely large systems and led major transformations, which proves I can solve high-scale problems in any company.", "overclaim", "It turns bounded resume facts into a universal capability claim and removes the evidence boundary." ]
      ],
      sources: %i[fullstack smarttv frontend],
      verified: [
        "More than ten years of full-stack experience across Rails, Go, React, React Native, and TypeScript.",
        "Rails APIs handling more than 100 million requests per day.",
        "Eight microfrontends across five squads and Smart TV delivery for Samsung Tizen and LG webOS."
      ]
    },
    {
      prompt: "You worked on Rails APIs handling more than 100 million requests per day. What did reliability responsibility mean in that environment?",
      context: "Separate the documented scale and responsibilities from any implementation detail the resume does not establish.",
      answer: "In that environment, reliability meant treating latency, incidents, and data correctness as product responsibilities rather than cleanup work. My resume documents Rails APIs handling more than 100 million requests per day, targeted API and query optimisations, and strong automated test coverage. It also records work on a platform designed for Brazilian Central Bank requirements. I would explain the responsibility through the signals I owned—latency, query behaviour, incident response, and regression protection—then clarify the exact service boundary if the interviewer wants a deeper example.",
      short: "At more than 100 million Rails API requests per day, reliability meant owning latency, query behaviour, incident response, and regression protection as product concerns.",
      deep: "The scale made reliability an everyday engineering constraint. The documented evidence includes Rails APIs handling more than 100 million requests per day, targeted API and query tuning, and about 95% RSpec coverage, alongside work on a platform designed for Brazilian Central Bank requirements. I would describe the observed performance or correctness problem first, the bounded change I was responsible for, and the verification signal. I would not invent a particular database plan or incident mechanism unless I could tie it to the specific project example being discussed.",
      distractors: [
        [ "At that traffic level, the main answer is horizontal scaling, because adding more application servers resolves the reliability risk.", "single-mechanism shortcut", "The resume confirms scale, not that one scaling mechanism explained or resolved every reliability concern." ],
        [ "The APIs were already mature, so reliability mostly meant keeping the existing system stable and avoiding significant changes.", "unsupported operating claim", "The resumes mention optimisation, incident response, and compliance work; they do not establish a change-avoidance strategy." ],
        [ "I guaranteed that every request was fast and error-free by maintaining high test coverage across the Rails application.", "absolute guarantee", "Test coverage is supporting evidence, not proof that every production request was fast or error-free." ]
      ],
      sources: %i[fullstack],
      verified: [
        "Rails APIs handling more than 100 million requests per day.",
        "Targeted Rails API optimisation, query tuning, incident response, and about 95% RSpec coverage.",
        "A platform designed for Brazilian Central Bank requirements."
      ]
    },
    {
      prompt: "Tell me about leading a migration from a monolithic frontend to eight microfrontends across five squads.",
      context: "Explain the delivery outcome and the coordination trade-off without presenting microfrontends as a universal rule.",
      answer: "I led a migration from a monolithic frontend to eight microfrontends across five squads using Module Federation. The practical goal was independent delivery: the resume reports deployment time moving from roughly two days to under one hour. The benefit was team autonomy, but the trade-off was a larger coordination surface for shared contracts, integration, and consistency. I would choose that structure again only when team boundaries and release independence justify the operational overhead; otherwise, a well-modularised application can be the simpler option.",
      short: "I led a move to eight microfrontends across five squads, reducing reported deployment time from about two days to under one hour while accepting more coordination around shared contracts.",
      deep: "I led the migration from a monolithic frontend to eight microfrontends across five squads using Module Federation. The documented outcome was deployment time moving from roughly two days to under one hour, but the resume does not define the exact measurement window or every step included in that number. I would frame the decision around team and deployment boundaries rather than fashion: autonomy was the advantage, while integration, shared dependencies, consistency, and observability became more explicit coordination costs. The switch condition is organisational as much as technical—if independent ownership and deployment cadence do not repay those costs, I would prefer a modular monolith.",
      distractors: [
        [ "We split the monolith into microfrontends because smaller repositories are always easier to maintain and deploy independently.", "universal rule", "Repository size alone does not justify the runtime and coordination costs of microfrontends." ],
        [ "The migration was successful because each squad could choose its own stack without needing shared standards or integration contracts.", "autonomy without boundaries", "Independent delivery still requires deliberate contracts and consistency; the resume does not claim unrestricted stack choice." ],
        [ "The main result was moving to Module Federation, which modernised the architecture and automatically accelerated every release.", "mechanism as outcome", "Module Federation is the mechanism; the evidence is the measured lead-time change and team boundary." ]
      ],
      sources: %i[frontend fullstack],
      verified: [
        "Migration from a monolithic frontend to eight microfrontends across five squads.",
        "Module Federation was used.",
        "Deployment time moved from roughly two days to under one hour."
      ]
    },
    {
      prompt: "Describe a Smart TV performance problem you solved on Samsung Tizen and LG webOS.",
      context: "Use the measurement and change recorded in the Smart TV resume; do not imply laboratory-grade causality beyond it.",
      answer: "On Samsung Tizen and LG webOS, I worked within tight memory and CPU constraints, so I used the Performance API to establish a channel-change baseline instead of optimising by feel. The resume records a reduction of roughly one third after moving EPG pagination to the server side. I would present that as the observed result of the change, while keeping the causal claim bounded to the measured scenario. The broader lesson was to instrument the user-visible path first and move work away from the device when constrained hardware is the bottleneck.",
      short: "I measured Smart TV channel-change time with the Performance API and the resume records roughly a one-third reduction after server-side EPG pagination.",
      deep: "The environment was Samsung Tizen and LG webOS, where memory and CPU limits make browser-style assumptions risky. I used the Performance API to baseline the user-visible channel-change path, and the resume records roughly a one-third reduction after EPG pagination moved to the server side. I would explain the device constraint, the measurement, the bounded change, and the observed outcome in that order. I would also separate this performance story from the playback stack—Bitmovin and multi-DRM are documented experience, but they are not claimed as the cause of this particular improvement.",
      distractors: [
        [ "Smart TVs are slow devices, so I moved all EPG work to the server and that made channel changes consistently fast on every model.", "unbounded generalisation", "The resume records a measured improvement, not a guarantee across every device model or condition." ],
        [ "I replaced the player with Bitmovin and multi-DRM, which reduced channel-change time by roughly one third.", "false causality", "Bitmovin and multi-DRM are documented, but the recorded performance change is tied to server-side EPG pagination." ],
        [ "The best optimisation was reducing animation and visual complexity because rendering is always the main Smart TV bottleneck.", "unsupported bottleneck", "The documented example measured the channel-change path and changed EPG pagination, not animation complexity." ]
      ],
      sources: %i[smarttv],
      verified: [
        "Smart TV work on Samsung Tizen and LG webOS under memory and CPU constraints.",
        "Performance API measurement of the channel-change path.",
        "Roughly one-third reduction associated with server-side EPG pagination."
      ]
    },
    {
      prompt: "Walk me through your approach to retry-safe payment and Pix processing.",
      context: "Connect the Rails and Go experience, including the exactly-once processing guarantee for retried payment messages.",
      answer: "I treat retries as part of the payment contract, not as an exceptional path. In Rails payment and checkout work, I built idempotent state transitions, auditable records, isolated Sidekiq queues, bounded backoff, and dead-letter handling so a retried job never duplicated a charge. In Go Pix settlement services, I used a transactional outbox, idempotent inbox, and dead-letter queues to guarantee exactly-once processing of retried payment messages. I would explain the state boundary, retry path, and recovery behaviour as one reliability design.",
      short: "For retry-safe payments, I make state transitions idempotent and auditable, isolate retry policies, and contain failed work with dead-letter handling; my Go Pix work also used outbox and inbox boundaries.",
      deep: "My approach starts by assuming retries and partial failure will happen. On the Rails payment path, I used idempotent operations, explicit state transitions, auditable records, isolated Sidekiq queues, bounded retries with backoff, and dead-letter handling so retried jobs did not duplicate charges. On the Go Pix settlement path, I combined a transactional outbox, idempotent inbox, and dead-letter queues to guarantee exactly-once processing of retried payment messages. Together, those mechanisms protected the business transition and preserved a clear recovery trail.",
      distractors: [
        [ "I prevent duplicate payments by allowing each message to retry only once and then asking an operator to resolve any failure manually.", "retry suppression", "Limiting retries does not establish idempotency and can turn transient failures into manual data loss or delay." ],
        [ "A transactional outbox guarantees exactly-once delivery, so consumers do not need their own duplicate protection or recovery path.", "exactly-once overclaim", "An outbox alone does not remove duplicate delivery; the resume separately records an idempotent inbox and dead-letter handling." ],
        [ "The safest payment architecture is a single database transaction covering every internal service and external payment provider.", "unrealistic atomic boundary", "External systems do not generally participate in one local transaction, so recovery and idempotency remain necessary." ]
      ],
      sources: %i[fullstack],
      verified: [
        "Idempotent and auditable Rails payment and checkout state transitions.",
        "Sidekiq queue isolation, backoff, and dead-letter handling.",
        "Go Pix settlement services using transactional outbox, idempotent inbox, and dead-letter handling."
      ]
    },
    {
      prompt: "Tell me about replacing synchronous bottlenecks with event-driven communication across critical services.",
      context: "Focus on the engineering decision, the four-service scope, and the operational trade-offs introduced by asynchronous processing.",
      answer: "At Bornlogic, I eliminated synchronous bottlenecks across four critical services by introducing Apache Kafka for asynchronous event-driven communication. The decision reduced direct coupling on the critical path and let services process work independently. I would explain that the gain came with new responsibilities around message contracts, retry behaviour, observability, and consumer recovery. My approach was to use asynchronous communication where the workflow benefited from decoupling, while keeping direct calls for paths that still required an immediate response.",
      short: "I introduced Kafka across four critical services to remove synchronous bottlenecks, trading direct coupling for explicit message, retry, observability, and recovery responsibilities.",
      deep: "The problem was synchronous coupling across four critical services. I introduced Apache Kafka so those services could exchange events without holding the entire workflow on a chain of direct calls. That improved independence on the critical path, but it also changed the failure model: message contracts, duplicate handling, retries, monitoring, and consumer recovery became first-class concerns. I would present the decision as selective rather than ideological. If a caller genuinely needs an immediate result, a synchronous boundary can remain appropriate; where work can progress independently, the event-driven path gives better isolation.",
      distractors: [
        [ "I replaced all synchronous calls with Kafka because asynchronous communication is always more scalable and reliable.", "universal architecture rule", "The experience covers four critical services, not a rule that every request path should become asynchronous." ],
        [ "Kafka solved the bottlenecks by guaranteeing that consumers processed every message exactly once without duplicate handling.", "delivery guarantee overclaim", "Event transport does not remove the need to design retries, idempotency, and consumer recovery." ],
        [ "The main improvement was adopting a modern event platform, so the internal service contracts no longer required close ownership.", "tool as outcome", "The result came from changing service interaction boundaries; contracts become more important, not less." ]
      ],
      sources: %i[fullstack],
      verified: [
        "Apache Kafka was introduced for asynchronous event-driven communication.",
        "The work eliminated synchronous bottlenecks across four critical services.",
        "The role included accountability for reliability and incident response."
      ]
    },
    {
      prompt: "How did you reduce CI time in a monorepo of fifteen applications without slowing independent teams?",
      context: "Connect repository structure, caching, and measured delivery outcomes rather than discussing build tools in isolation.",
      answer: "I implemented TurboRepo across a monorepo of fifteen applications and shared libraries, using local and remote caching to avoid repeating unchanged work. The CI pipeline fell from twenty-five minutes to eight minutes, and single-package pull requests completed in under three minutes. The important part was matching the build graph to package boundaries, so teams could keep shared code without paying the cost of rebuilding everything. I would measure success through repeatable pipeline time and independent package delivery, not simply through adopting TurboRepo.",
      short: "I introduced TurboRepo with local and remote caching across fifteen applications, reducing CI from twenty-five to eight minutes and single-package PRs to under three minutes.",
      deep: "The monorepo contained fifteen applications plus shared libraries, so a naive pipeline made every change pay for work it had not affected. I implemented TurboRepo with local and remote caching and aligned CI execution with package boundaries. The measured result was a reduction from twenty-five minutes to eight minutes for the pipeline, with single-package pull requests under three minutes. The architectural benefit was preserving shared ownership while letting focused changes move quickly. I would keep invalidation correctness and reproducibility ahead of a superficially high cache-hit rate.",
      distractors: [
        [ "I split the monorepo into separate repositories because independent teams cannot deliver efficiently from shared source control.", "structure-only solution", "The confirmed result came from improving the existing monorepo build graph and caching, not abandoning shared libraries." ],
        [ "TurboRepo automatically reduced CI time because it detects every dependency and makes cache invalidation risk-free.", "automation overclaim", "The tool supports caching, but package boundaries and correct invalidation still require deliberate engineering." ],
        [ "The main goal was maximizing cache hits, even when that meant reusing outputs across loosely related build environments.", "unsafe metric", "Fast CI is useful only when cached outputs remain correct and reproducible for the relevant environment." ]
      ],
      sources: %i[fullstack frontend],
      verified: [
        "TurboRepo covered fifteen applications and shared libraries.",
        "Local and remote caching were implemented.",
        "CI moved from twenty-five minutes to eight minutes, with single-package pull requests under three minutes."
      ]
    },
    {
      prompt: "Describe how you reduced a critical list load time from seven seconds to two seconds.",
      context: "Explain the measurement, rendering work, and virtualization decision under the same data volume.",
      answer: "At Bornlogic, I reduced a critical list component’s load time from seven seconds to two seconds under the same data volume through targeted render optimisation and virtualization. I first kept the workload constant so the comparison represented an application improvement rather than less data. Then I focused the interface on rendering only the work required for the visible experience. I would present this as a measured performance story: baseline, constrained change, repeated measurement, and the user-visible result.",
      short: "I reduced a critical list from seven seconds to two seconds at the same data volume by targeting render work and applying virtualization.",
      deep: "The list took seven seconds to load at the target data volume. I kept that volume constant, profiled the rendering path, and applied targeted render optimisation and virtualization so the interface performed less unnecessary work. The measured load time fell to two seconds. The important reasoning was to preserve the comparison boundary: changing the dataset would have made the metric less useful. I would also distinguish initial load, interaction responsiveness, and memory behaviour instead of treating one timing number as the whole performance profile.",
      distractors: [
        [ "I reduced the load time mainly by returning fewer records, which is the simplest way to make any large list faster.", "changed workload", "The confirmed comparison kept the same data volume and improved the rendering strategy." ],
        [ "Virtualization guarantees good performance for every list, so profiling the component was unnecessary once we chose that library pattern.", "mechanism before measurement", "The result came from targeted measurement and optimisation; virtualization is not a universal substitute for profiling." ],
        [ "The seven-to-two-second improvement proves every interaction in the application became faster by the same proportion.", "metric overextension", "The measurement belongs to one critical list load path, not every interaction in the application." ]
      ],
      sources: %i[smarttv frontend],
      verified: [
        "A critical list component loaded in seven seconds before the work.",
        "Targeted render optimisation and virtualization were applied under the same data volume.",
        "The resulting load time was two seconds."
      ]
    },
    {
      prompt: "Tell me about your application-security work as part of Enjoei’s Yellow Team.",
      context: "Describe collaboration with the Red Team, concrete vulnerability classes, and the architectural remediation work.",
      answer: "At Enjoei, I worked in the Yellow Team alongside the Red Team, turning identified vulnerabilities into application changes. I led remediation across Rails APIs for injection, privilege escalation, insecure direct object references, authentication, authorization, and data exposure. I also refactored checkout by decoupling order validation from the monolith through service isolation, which reduced the attack surface and made security auditing simpler. My role connected the finding to the code path, implemented the repair, and preserved maintainability rather than treating security as a separate review step.",
      short: "In Enjoei’s Yellow Team, I partnered with the Red Team to remediate injection, privilege escalation, IDOR, authorization, and data-exposure risks in Rails systems.",
      deep: "The Red Team identified attack paths, and my Yellow Team responsibility was to convert those findings into durable product changes. I worked across authentication, authorization, data exposure, injection, privilege escalation, and IDOR patterns in Rails APIs. One architectural example was checkout: I decoupled order validation from the monolith using service isolation, reducing the attack surface and simplifying auditing. I would describe both the immediate vulnerability repair and the structural change that made the same class of issue harder to reintroduce.",
      distractors: [
        [ "The Red Team owned security, so my responsibility was mainly to apply the patches they specified after each assessment.", "passive ownership", "The confirmed role involved designing and implementing fixes daily with the Red Team, including architectural remediation." ],
        [ "We solved authorization risks by adding more controller checks wherever a security report mentioned a vulnerable endpoint.", "local patching only", "The work included broader authentication, authorization, data-exposure, and service-boundary changes." ],
        [ "Service isolation made checkout secure by removing the need for application-level authorization inside the new boundary.", "boundary as guarantee", "Isolation can reduce attack surface, but authorization and validation remain explicit responsibilities." ]
      ],
      sources: %i[fullstack frontend],
      verified: [
        "Daily Yellow Team collaboration with the Red Team.",
        "Remediation covered injection, privilege escalation, IDOR, authentication, authorization, and data exposure.",
        "Checkout order validation was decoupled from the monolith, reducing attack surface and simplifying auditing."
      ]
    },
    {
      prompt: "How did you lead engineers while remaining accountable for delivery and technical quality?",
      context: "Use the team sizes and concrete leadership activities from your experience rather than generic management language.",
      answer: "At Bornlogic, I led eight engineers through code reviews, technical interviews, and structured knowledge-sharing while remaining hands-on with Rails, frontend architecture, reliability, and delivery. Earlier, at Stormgroup, I mentored three developers while introducing stronger RSpec and TDD/BDD practices. My leadership style is to make decisions and quality standards visible: review the reasoning, connect it to the production outcome, and create repeatable ways for the team to apply it without waiting for one person.",
      short: "I led eight engineers through reviews, interviews, and knowledge sharing, and previously mentored three developers while strengthening testing practices.",
      deep: "My leadership has been technical and delivery-oriented. At Bornlogic, I led eight engineers while contributing directly to architecture, reliability, code reviews, hiring interviews, and structured knowledge sharing. At Stormgroup, I mentored three developers and helped establish RSpec with TDD/BDD practices. I try to turn individual judgment into team capability by explaining the decision boundary, reviewing evidence rather than style alone, and documenting or demonstrating a practice until others can own it independently.",
      distractors: [
        [ "As tech lead, I made the final architectural decisions so the team could focus on implementation without prolonged technical debate.", "centralised decision making", "The confirmed activities emphasise reviews, interviews, knowledge sharing, and team capability rather than one-person control." ],
        [ "I measured leadership mainly by code volume because staying the strongest individual contributor sets the clearest standard.", "individual-output proxy", "The experience includes mentoring and repeatable engineering practices, not code volume as the leadership outcome." ],
        [ "Once testing standards reached high coverage, I could delegate quality entirely to CI and focus only on roadmap delivery.", "automation replaces judgment", "Coverage supported critical modules, while reviews and technical leadership remained active responsibilities." ]
      ],
      sources: %i[fullstack smarttv frontend],
      verified: [
        "Led eight engineers through code reviews, technical interviews, and structured knowledge-sharing sessions.",
        "Established more than 95% RSpec coverage across critical modules.",
        "Mentored three developers while leading RSpec and TDD/BDD adoption at Stormgroup."
      ]
    },
    {
      prompt: "What were the hardest engineering boundaries in shipping one React Native OTT codebase to Samsung Tizen and LG webOS?",
      context: "Discuss the television-specific constraints, playback stack, and cross-platform decisions rather than basic React concepts.",
      answer: "The hard boundaries were television-specific: remote-control navigation, limited memory and CPU, large content rails, EPG behaviour, and playback differences across Samsung Tizen and LG webOS. I shipped the platforms from one React Native codebase through ReNative and integrated Bitmovin for Live, VOD, and catch-up with Widevine, PlayReady, and FairPlay. The shared codebase reduced duplication, but platform behaviour still needed explicit handling. I treated common product logic as shared and kept device-specific performance, navigation, and playback adaptations at clear boundaries.",
      short: "I shipped one ReNative codebase to Tizen and webOS while isolating device-specific navigation, memory, rendering, EPG, playback, and DRM behaviour.",
      deep: "A shared React Native codebase was valuable only if it respected the constraints of each TV platform. The product covered Live, VOD, and catch-up, with Bitmovin and multi-DRM across Widevine, PlayReady, and FairPlay. I had to account for remote focus navigation, memory and CPU limits, incremental rail rendering, EPG scale, audio and subtitle switching, channel changes, and real-world network behaviour. My design principle was to share product flows and stable abstractions, while isolating device-specific capabilities and performance work instead of hiding them behind a false assumption of complete parity.",
      distractors: [
        [ "Because ReNative provided a shared codebase, platform-specific Tizen and webOS behaviour could remain inside the framework layer.", "false platform parity", "The confirmed work explicitly handled navigation, memory, rendering, playback, and device-specific constraints." ],
        [ "The main challenge was responsive styling because television screens use larger dimensions than mobile devices.", "basic surface focus", "The senior constraints were remote navigation, hardware limits, EPG, playback, DRM, and rendering throughput." ],
        [ "Using Bitmovin removed most playback differences, so the application only needed one universal DRM and channel-change path.", "player abstraction overclaim", "The experience included multiple DRM systems and platform-aware behaviour under real network conditions." ]
      ],
      sources: %i[smarttv fullstack frontend],
      verified: [
        "One React Native codebase shipped through ReNative to Samsung Tizen and LG webOS.",
        "The OTT product covered Live, VOD, catch-up, Bitmovin, Widevine, PlayReady, and FairPlay.",
        "The work addressed remote navigation, memory, rendering performance, EPG, and incremental content rails."
      ]
    },
    {
      prompt: "Tell me about owning payment processing for more than 2.5 million clients per month.",
      context: "Connect payment responsibility, tokenization, database performance, and release safety across broadcast platforms.",
      answer: "At Stormgroup for Globo and Projac, I owned payment processing for more than 2.5 million clients per month across multiple broadcast platforms. I delivered credit-card integration and tokenization, improved critical API response times by thirty percent through PostgreSQL and MariaDB query optimisation, and introduced a CI/CD pipeline with zero-downtime deployments. I would frame the experience around protecting the payment path while improving performance and release safety at the same time, because scale is meaningful only when transactions and deployments remain reliable.",
      short: "I owned payment processing for more than 2.5 million monthly clients, including card tokenization, a thirty-percent API improvement, and zero-downtime delivery.",
      deep: "The payment path served more than 2.5 million clients monthly across multiple broadcast platforms. I owned credit-card integration and tokenization, while also improving the supporting system: targeted PostgreSQL and MariaDB optimisation reduced critical API response times by thirty percent, and a new CI/CD pipeline enabled zero-downtime deployments instead of manual releases. The story connects business scale to engineering controls—secure payment handling, measured database performance, and safer deployment—rather than presenting the client count as an isolated headline.",
      distractors: [
        [ "At that client volume, the primary solution was scaling the database vertically so payment logic and releases could stay unchanged.", "single scaling lever", "The confirmed work combined tokenization, query optimisation, and deployment changes rather than one capacity adjustment." ],
        [ "Tokenization removed payment risk, allowing the team to prioritise API performance over release controls.", "security mechanism as guarantee", "Tokenization addresses one boundary; release safety and transaction reliability remained important responsibilities." ],
        [ "The thirty-percent API improvement demonstrates that every payment transaction completed thirty percent faster end to end.", "metric scope expansion", "The confirmed metric covers critical API endpoints, not every stage of the complete payment lifecycle." ]
      ],
      sources: %i[fullstack smarttv frontend],
      verified: [
        "Owned payment processing for more than 2.5 million clients monthly across broadcast platforms.",
        "Delivered credit-card integration and tokenization.",
        "Critical API response times improved by thirty percent and CI/CD enabled zero-downtime deployments."
      ]
    }
  ].freeze

  def self.cards(cards)
    indexed = Array(cards).index_by { |card| card.fetch(:key).to_s }
    CARD_KEYS.zip(PROFILES).filter_map do |key, profile|
      decorate(indexed[key], profile) if indexed[key]
    end
  end

  def self.interview_roles
    INTERVIEW_ROLES
  end

  def self.role_metadata(role = nil)
    return ROLE_METADATA if role.nil?

    ROLE_METADATA[role.to_s]
  end

  # Role cards have their own immutable IDs and target. They must never be
  # decorated career cards: Arena resolves a persisted ID on every show and
  # grade, while the career cards remain part of the legacy assessment deck.
  def self.role_cards(cards, role: nil, decks: ROLE_DECKS)
    roles = role.to_s.present? ? [ role.to_s ] : INTERVIEW_ROLES
    return [] unless roles.all? { |value| INTERVIEW_ROLES.include?(value) }

    indexed = Array(cards).index_by { |card| card.fetch(:key).to_s }
    roles.flat_map do |role_name|
      decks.fetch(role_name).filter_map do |definition|
        card_id = definition.fetch(:id)
        profile = role_profile(role_name, definition, card_id)
        raw = indexed[CARD_KEYS.fetch(definition.fetch(:profile))]
        next unless raw

        decorate(raw, profile).merge(
          key: card_id,
          target: "interview",
          interview_role: role_name,
          learning: profile.fetch(:learning),
          recall_check: profile.fetch(:recall_check),
          recall: {
            "active_recall_cue" => "Answer as a #{role_name.tr('_', ' ')} candidate: name the responsibility, one supported result, and the limit of the claim."
          },
          content_version: ROLE_CONTENT_VERSION
        )
      end
    end
  end

  def self.role_profile(role, definition, card_id)
    base = PROFILES.fetch(definition.fetch(:profile)).deep_dup
    overrides = definition.except(:id, :profile).deep_dup
    profile = base.merge(overrides)
    profile = profile.merge(INTRO_EVIDENCE.fetch(role)) if INTRO_CARD_IDS.include?(card_id)
    profile[:learning] ||= {
      "answer_structure" => [ "Answer the question directly.", "Use one resume-backed responsibility and result.", "Name the relevant trade-off or boundary." ],
      "useful_phrases" => [ "A concrete example is…", "The measured result was…", "I would keep that claim bounded to…" ],
      "pt_help" => "Responda primeiro e use um exemplo do currículo. Métricas pertencem ao cenário citado, não a toda a sua carreira."
    }
    profile[:recall_check] = {
      "minimum_words" => 15,
      "required_groups" => 2,
      "key_points" => CARD_RECALL_CHECKS.fetch(card_id)
    }
    profile[:interview_role] = role
    profile[:role_card_id] = card_id
    profile[:learning]["reasoning_questions"] = CARD_REASONING_QUESTIONS.fetch(card_id).deep_dup
    profile[:learning]["answer_versions"] = {
      "short" => profile.fetch(:short),
      "medium" => profile.fetch(:answer),
      "deep" => profile.fetch(:deep)
    }
    profile
  end
  private_class_method :role_profile

  def self.decorate(raw, profile)
    card = raw.deep_dup
    variants = card.fetch(:variants).deep_dup
    variants["initial"] = variants.fetch("initial").merge(
      "prompt" => profile.fetch(:prompt),
      "context" => profile.fetch(:context),
      "best_answer" => profile.fetch(:answer),
      "distractors" => distractors(profile),
      "feedback" => feedback(profile),
      "critical_thinking" => critical_thinking(profile)
    )
    variants = role_variants(variants, profile) if profile.key?(:role_card_id)
    sources = profile.fetch(:sources).map { |source_key| source_for(source_key) }
    card.merge(
      prompt: profile.fetch(:prompt),
      context: profile.fetch(:context),
      answer_text: profile.fetch(:answer),
      feedback: feedback(profile),
      sources: sources,
      source: sources.first,
      provenance: provenance(profile),
      variants: variants,
      _response_versions: {
        "short" => profile.fetch(:short),
        "medium" => profile.fetch(:answer),
        "deep" => profile.fetch(:deep)
      },
      content_version: "resume-interview-2026-08-29"
    )
  end
  private_class_method :decorate

  def self.role_variants(variants, profile)
    authored = CARD_VARIANT_CONTENT.fetch(profile.fetch(:role_card_id))
    variants.merge(
      "follow_up" => authored_variant(authored.fetch(:follow_up), profile),
      "delayed_variant" => authored_variant(authored.fetch(:delayed_variant), profile)
    )
  end
  private_class_method :role_variants

  def self.authored_variant(definition, profile)
    prompt, answer, distractor_texts = definition
    {
      "prompt" => prompt,
      "context" => "Answer the changed interviewer question directly and keep the claim inside the supplied resume evidence.",
      "best_answer" => answer,
      "distractors" => distractor_texts.map do |text|
        { "text" => text, "trap" => "role-specific overclaim", "why_wrong" => "This answer drops the documented constraint or substitutes an unsupported mechanism." }
      end,
      "feedback" => feedback(profile),
      "critical_thinking" => critical_thinking(profile)
    }
  end
  private_class_method :authored_variant

  def self.distractors(profile)
    profile.fetch(:distractors).map do |text, trap, why_wrong|
      { "text" => text, "trap" => trap, "why_wrong" => why_wrong }
    end
  end
  private_class_method :distractors

  def self.feedback(profile)
    {
      "register" => "Lead with your responsibility and the confirmed result; avoid promotional superlatives.",
      "hedging" => "Use the resume metric directly, then state the relevant test boundary precisely.",
      "precision" => "Keep actor, scale, mechanism, and observed outcome in separate clauses.",
      "grammar" => "Use past simple for the completed work and present simple for the lesson you carry forward.",
      "pragmatics" => "Answer in first person, stop after the evidence, and invite the interviewer to choose the next deep dive.",
      "topic" => "Rehearse the verified resume facts on this card and keep the answer direct."
    }
  end
  private_class_method :feedback

  def self.critical_thinking(profile)
    {
      "problem_frame" => "Present one resume-backed responsibility and result without turning it into a universal capability claim.",
      "claim_map" => {
        "fact" => profile.fetch(:verified).join(" "),
        "inference" => "The example suggests transferable engineering judgment, but the new role and constraints still need discussion.",
        "assumption" => "The interviewer values this example for the role being discussed.",
        "unknown" => nil
      },
      "comparison" => {
        "applicable" => false,
        "rejected_alternative" => "A broader claim with no matching resume evidence.",
        "hard_constraint" => "The answer must remain inside the supplied resume evidence.",
        "decision_rule" => "Prefer the most relevant verified example, then label any missing detail before expanding it."
      },
      "failure_probe" => { "prompt" => "Which sentence would become an overclaim if the interviewer changed the role, scale, or test boundary?" },
      "evidence_check" => {
        "basis" => "Facts supplied and confirmed directly by the user through the resume PDFs."
      },
      "certainty" => {
        "level" => "medium",
        "rationale" => "The supplied resume facts are high-confidence evidence, but any engineering recommendation remains conditional on the role, constraints, and evidence in the interview.",
        "update_trigger" => "Update the recommendation when the interviewer changes the role, scale, failure tolerance, or supplies technical evidence; update the biography only when a resume fact changes."
      }
    }
  end
  private_class_method :critical_thinking

  def self.source_for(key)
    file = SOURCE_FILES.fetch(key)
    {
      "repo" => "user-supplied resume",
      "path" => file.fetch("path"),
      "note" => "Read locally for Interview Mode; the PDF itself is not bundled or served by the app."
    }
  end
  private_class_method :source_for

  def self.provenance(profile)
    keys = profile.fetch(:sources).uniq
    {
      "evidence_class" => "resume_derived",
      "project" => "User-supplied resume interview profile",
      "repository" => "local-user-source",
      "files" => keys.map do |key|
        file = SOURCE_FILES.fetch(key)
        {
          "path" => file.fetch("path"),
          "commit" => file.fetch("fingerprint"),
          "identifier_kind" => "sha256",
          "claim" => "Local source fingerprint for the resume facts listed in verified_claims."
        }
      end,
      "verified_claims" => profile.fetch(:verified),
      "confirmation_required" => [],
      "safe_interview_version" => profile.fetch(:answer),
      "confidentiality" => {
        "level" => "medium",
        "note" => "Use only resume-level facts; do not disclose contact details or protected employer implementation details."
      }
    }
  end
  private_class_method :provenance
end
