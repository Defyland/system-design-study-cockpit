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
      "fingerprint" => "4fdba1021da478356361ad2c9f473be987369ad0fb47ac1b0cf84ca4bdb810b1"
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
      answer: "I led a migration from a monolithic frontend to eight microfrontends across five squads using Module Federation. The practical goal was independent delivery: the resume records release lead time moving from roughly two days to under one hour. The benefit was team autonomy, but the trade-off was a larger coordination surface for shared contracts, integration, and consistency. I would choose that structure again only when team boundaries and release independence justify the operational overhead; otherwise, a well-modularised application can be the simpler option.",
      short: "I led a move to eight microfrontends across five squads, reducing release lead time from about two days to under one hour while accepting more coordination around shared contracts.",
      deep: "I led the migration from a monolithic frontend to eight microfrontends across five squads using Module Federation. The documented outcome was release lead time moving from roughly two days to under one hour, enabling more independent releases. I would frame the decision around team and deployment boundaries rather than fashion: autonomy was the advantage, while integration, shared dependencies, consistency, and observability became more explicit coordination costs. The switch condition is organisational as much as technical—if independent ownership and release cadence do not repay those costs, I would prefer a modular monolith.",
      distractors: [
        [ "We split the monolith into microfrontends because smaller repositories are always easier to maintain and deploy independently.", "universal rule", "Repository size alone does not justify the runtime and coordination costs of microfrontends." ],
        [ "The migration was successful because each squad could choose its own stack without needing shared standards or integration contracts.", "autonomy without boundaries", "Independent delivery still requires deliberate contracts and consistency; the resume does not claim unrestricted stack choice." ],
        [ "The main result was moving to Module Federation, which modernised the architecture and automatically accelerated every release.", "mechanism as outcome", "Module Federation is the mechanism; the evidence is the measured lead-time change and team boundary." ]
      ],
      sources: %i[frontend fullstack],
      verified: [
        "Migration from a monolithic frontend to eight microfrontends across five squads.",
        "Module Federation was used.",
        "Release lead time moved from roughly two days to under one hour."
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
        "level" => "high",
        "rationale" => "The user directly confirmed the facts represented in the supplied resumes.",
        "update_trigger" => "Update only if the user supplies new or corrected information."
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
