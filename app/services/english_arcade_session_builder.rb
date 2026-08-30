# Builds the closed-book English interview loop without embedding the standalone
# Vite app. The fixture adapter is deliberately replaceable: an Opus/content
# provider can implement `cards_for(target)` and be injected at boot or in a
# test without changing the session, grading, or scheduling contract.
require "digest"
require "set"
require "yaml"
require_relative "english_arcade_curriculum"
require_relative "english_arcade_attempt_contract"
require_relative "english_arcade_resume_interview_profile"
require_relative "../../lib/english_arcade/schema"
require_relative "../../lib/english_arcade/pack_validator"

class EnglishArcadeSessionBuilder
  REQUIRED_MOCK_COMPLETED_STATES = %w[scheduled mastered revealed].freeze
  TARGETS = {
    "dsa" => { label: "DSA & algorithms", short_label: "DSA", focus: "patterns, invariants, complexity, and Ruby traps" },
    "ruby" => { label: "Ruby", short_label: "Ruby", focus: "object model, blocks, performance, and concurrency" },
    "rails" => { label: "Ruby on Rails", short_label: "Rails", focus: "request flow, data access, jobs, caching, and security" },
    "react" => { label: "React", short_label: "React", focus: "rendering, state, effects, fetching, and accessibility" },
    "golang" => { label: "Golang", short_label: "Go", focus: "interfaces, goroutines, context, errors, and profiling" },
    "elixir" => { label: "Elixir", short_label: "Elixir", focus: "processes, OTP, back-pressure, and fault tolerance" },
    "databases" => { label: "Databases", short_label: "Databases", focus: "data models, query plans, isolation, recovery, and trade-offs" },
    "general" => { label: "General conversation", short_label: "General", focus: "professional rapport, clarification, disagreement, and behavioural narratives" },
    "career" => { label: "Career narrative", short_label: "Career", focus: "truthful introductions, project stories, evidence boundaries, and adaptation" },
    "rails_experience" => { label: "Rails experience", short_label: "Rails experience", focus: "evidence-bounded Rails stories, incidents, trade-offs, and outcomes" },
    "go_experience" => { label: "Go experience", short_label: "Go experience", focus: "inspectable Go projects, concurrency boundaries, failures, and trade-offs" },
    "elixir_experience" => { label: "Elixir experience", short_label: "Elixir experience", focus: "inspectable Elixir projects, OTP decisions, failure modes, and limits" },
    "system_design" => { label: "System design", short_label: "System design", focus: "requirements, capacity, source of truth, and failure trade-offs" },
    "salesforce" => { label: "Salesforce (elective)", short_label: "Salesforce", focus: "optional: governor limits, Apex, Flow, integration, and security" },
    "mixed" => { label: "Mixed practice", short_label: "Mixed", focus: "interleaved interview decisions across every target" },
    "interview" => { label: "Interview mode", short_label: "Interview", focus: "resume-backed stories, evidence boundaries, role relevance, and pragmatic phrasing" }
  }.freeze

  MODES = {
    "daily" => { label: "Daily drill", duration_seconds: 600 },
    "timed_30" => { label: "30-minute behavioural interview", duration_seconds: 30.minutes.to_i },
    "timed_45" => { label: "45-minute interview", duration_seconds: 45.minutes.to_i }
  }.freeze

  TARGET_ALIASES = {
    "dsa & algorithms" => "dsa",
    "system design" => "system_design",
    "system-design" => "system_design",
    "mixed practice" => "mixed",
    "interview mode" => "interview",
    "go" => "golang",
    "database" => "databases",
    "general conversation" => "general",
    "career narrative" => "career",
    "career story" => "career",
    "rails experience" => "rails_experience",
    "rails-experience" => "rails_experience",
    "go experience" => "go_experience",
    "go-experience" => "go_experience",
    "elixir experience" => "elixir_experience",
    "elixir-experience" => "elixir_experience"
  }.freeze

  Plan = Struct.new(
    :target, :target_label, :mode, :mode_label, :duration_seconds, :cards, :source,
    keyword_init: true
  )
  Choice = Struct.new(:id, :text, keyword_init: true)
  Card = Struct.new(
    :key, :target, :target_label, :prompt, :context, :options, :correct_choice,
    :answer_text, :feedback, :rephrase_prompt, :extension_prompt, :follow_up_prompt,
    :compression_prompt, :feynman, :black_box, :recall, :tags, :source, :sources,
    :provenance, :variants, :variant_id, :variant_digest, :variant_contract, :critical_thinking,
    :response_versions, :option_guides, :content_version,
    keyword_init: true
  )
  Grade = Struct.new(:correct, :feedback, :diagnostic_evidence, keyword_init: true)

  # These are intentionally small, stable records for the handoff window while
  # the content seat supplies richer target packs. They preserve the contract:
  # natural question/context, one best answer, distractors, feedback, and two
  # follow-up prompts. No answer key is emitted by `prompt_snapshot`.
  class FixtureAdapter
    TOPICS = {
      "dsa" => %w[sliding-window invariant recursion-vs-iteration hash-indexing graph traversal complexity Ruby-array-trap test-counterexample],
      "ruby" => %w[object-model blocks-and-yield enumerables allocation memoization threads-and-gvl errors-and-results value-object-design],
      "rails" => %w[request-lifecycle query-shape N+1-jobs-and-retries cache-invalidation authorization observability transactions deployment-safety],
      "react" => %w[render-purity state-ownership effect-boundaries data-fetching race-control accessibility rendering-cost memoization],
      "golang" => %w[interfaces goroutine-lifecycle channels context-cancellation error-wrapping profiling service-boundaries backpressure],
      "elixir" => %w[process-isolation supervision-trees immutability GenServer-backpressure fault-tolerance message-ordering telemetry release-safety],
      "databases" => %w[modeling-constraints indexes query-plans isolation locks replication partitioning migrations],
      "general" => %w[introduction small-talk clarification disagreement scope-negotiation STAR conflict incident-update],
      "career" => %w[introduction experience-walkthrough project-deep-dive evidence-boundary recruiter-adaptation engineer-adaptation stakeholder-adaptation difficult-follow-up what-would-change-now STAR-CARE concise-version narrative-compression],
      "rails_experience" => %w[request-boundary data-integrity provider-failure jobs-idempotency query-performance security-observability trade-off-clarification incident-narrative next-step evidence-limit audience-rephrase],
      "go_experience" => %w[service-boundary interfaces goroutine-lifetime context-cancellation idempotency backpressure profiling failure-recovery trade-off-clarification evidence-limit audience-rephrase],
      "elixir_experience" => %w[process-boundary supervision backpressure idempotency transaction-boundary cancellation fault-tolerance testing observability evidence-limit audience-rephrase],
      "salesforce" => %w[governor-limits bulkification Apex-vs-Flow integration-security sharing-model async-work stakeholder-tradeoff deployment],
      "system_design" => %w[requirements-capacity write-read-path source-of-truth consistency failure-mode queues observability Rails-mapping]
    }.freeze

    OPENINGS = {
      "dsa" => "I would state the invariant first, then give time and space complexity before choosing the implementation.",
      "ruby" => "I would name the object or execution boundary first, then explain the trade-off with one concrete Ruby example.",
      "rails" => "I would locate the request boundary first, then make the data, failure, and observability trade-offs explicit.",
      "react" => "I would separate render-time derivation from effects, then describe the ownership and user-visible failure mode.",
      "golang" => "I would name the goroutine or API lifetime first, then show how cancellation, errors, and back-pressure are bounded.",
      "elixir" => "I would identify the process boundary first, then explain supervision and the recovery behavior a caller can observe.",
      "databases" => "I would state the data invariant first, then explain the query, isolation, or recovery trade-off I would verify.",
      "general" => "I would answer directly, make the context explicit, and invite the interviewer to add the constraint that matters most.",
      "career" => "I would lead with a truthful through-line, choose one inspectable example, and make the evidence boundary explicit.",
      "rails_experience" => "I would name the Rails boundary and the observed behaviour first, then separate verified evidence from a hypothesis.",
      "go_experience" => "I would describe the Go service boundary and lifetime first, then state what the code proves and what still needs measurement.",
      "elixir_experience" => "I would identify the process or supervision boundary first, then explain the recovery behaviour and its evidence limit.",
      "salesforce" => "I would state the platform limit or security boundary first, then choose the smallest maintainable automation path.",
      "system_design" => "I would clarify the success metric and traffic shape first, then choose a source of truth and name the failure trade-off."
    }.freeze

    DISTRACTOR_TEMPLATES = [
      "I would jump straight to a library choice and leave the constraint implicit.",
      "I would promise that the happy path is enough and defer failure handling until production.",
      "I would give a universal rule without checking the workload, audience, or boundary."
    ].freeze

    def self.cards_for(target)
      # A fixture is not interview coverage. Canonical packs are unavailable
      # until their authored YAML passes strict validation; only elective
      # Salesforce may use this cold-checkout scaffold.
      return [] if EnglishArcade::Schema::CANONICAL_TARGETS.include?(target)

      topics = TOPICS.fetch(target) { TOPICS.values.flatten.first(8) }
      topics.each_with_index.map do |topic, index|
        answer = answer_for(target, topic, index)
        choices = [
          Choice.new(id: "a", text: answer),
          Choice.new(id: "b", text: DISTRACTOR_TEMPLATES[0]),
          Choice.new(id: "c", text: DISTRACTOR_TEMPLATES[1]),
          Choice.new(id: "d", text: DISTRACTOR_TEMPLATES[2])
        ]
        choices = choices.rotate((index + target.length) % choices.length)

        {
          key: "#{target}-#{index + 1}",
          target: target,
          topic: topic,
          prompt: "In a senior #{TARGETS.fetch(target)[:label]} interview, explain #{topic.tr("-", " ")} and name the first trade-off you would test.",
          context: "Answer closed-book in two or three sentences. The interviewer may ask for a rephrase or one extension.",
          choices: choices.map { |choice| { id: choice.id, text: choice.text } },
          correct_choice: choices.first.id,
          answer_text: answer,
          feedback: feedback_for(target, topic),
          rephrase_prompt: "Rephrase your answer for a non-specialist stakeholder without losing the caveat.",
          extension_prompt: "Extend the answer with one failure mode, metric, or follow-up question.",
          follow_up_prompt: nil,
          compression_prompt: nil,
          feynman: { "concept" => topic.tr("-", " "), "explain_to" => "a teammate", "constraint" => "Use one concrete boundary.", "self_check" => "Could they repeat the decision?" },
          black_box: { "symptom" => "The answer was generic.", "expected" => "A decision with evidence.", "actual" => "A vague claim.", "root_cause" => "The constraint was skipped.", "repair" => "State the boundary first." },
          recall: { "active_recall_cue" => "State the decision and evidence.", "leitner_start_box" => 1, "mastery_threshold" => 8 },
          tags: [ topic, target, "c2-register" ],
          source: "english-arcade-fixture-v1"
        }
      end
    end

    def self.answer_for(target, topic, index)
      opening = OPENINGS.fetch(target)
      suffixes = [
        "For #{topic.tr("-", " ")}, I would state the assumption, test a counterexample, and keep the recommendation proportional to the evidence.",
        "I would hedge the recommendation with the workload and audience, then name what would change my mind.",
        "I would make the boundary observable, describe the unhappy path, and avoid claiming certainty the data cannot support.",
        "I would compare the simplest viable option with its cost, latency, and recovery implications before optimizing.",
        "I would use a concrete example, check the edge case, and finish with a precise next step for the interviewer.",
        "I would separate the mechanism from the policy, then explain how I would test the decision safely.",
        "I would acknowledge the trade-off, state the invariant that must hold, and propose a reversible experiment.",
        "I would close by naming the metric or signal that tells us whether the decision worked."
      ]
      "#{opening} #{suffixes.fetch(index % suffixes.length)}"
    end

    def self.feedback_for(target, topic)
      {
        "register" => "Use a measured interview register: lead with the decision, then qualify it.",
        "hedging" => "Prefer 'I would', 'assuming', and 'I would verify' over absolute claims.",
        "precision" => "Name the boundary, workload, and observable signal instead of relying on a broad rule.",
        "grammar" => "Keep the conditional clause explicit and use a short cause → trade-off → action sequence.",
        "pragmatics" => "Answer the question first, then offer the caveat and invite the next constraint.",
        "topic" => "Revisit #{topic.tr("-", " ")} and connect it to one concrete failure mode."
      }
    end

    def self.target_metadata
      EnglishArcadeSessionBuilder::TARGETS
    end
  end

  # Prefers the validated YAML packs (or an injected content provider) when
  # they exist, while keeping a deterministic fixture for a fresh checkout.
  # The adapter normalizes both the publishable pack shape and the small
  # contract fixture shape into the private raw-card contract above.
  class ContentPackAdapter
    PROVENANCE_KEYS = EnglishArcade::Schema::REQUIRED_PROVENANCE_KEYS.freeze
    PROVENANCE_FILE_KEYS = EnglishArcade::Schema::REQUIRED_PROVENANCE_FILE_KEYS.freeze
    CONFIDENTIALITY_KEYS = EnglishArcade::Schema::REQUIRED_CONFIDENTIALITY_KEYS.freeze

    attr_reader :source_name

    def self.build
      production_directory = defined?(Rails) && Rails.root.join("db/seeds/english_arcade").directory?
      packs = load_pack_directory
      fixture = load_contract_fixture

      # A production directory is authoritative. If a pack is malformed or
      # absent, keep it unavailable rather than resurrecting generic cards from
      # the contract fixture. Fixtures remain a cold-checkout fallback only.
      merged = merge_packs(packs, fixture, allow_fixture_fallback: !production_directory)
      return new(merged, source_name: source_for(packs, fixture)) if merged.any? || production_directory

      nil
    rescue StandardError
      return new({}, source_name: "english-arcade-packs-invalid") if defined?(Rails) && Rails.root.join("db/seeds/english_arcade").directory?

      nil
    end

    def self.load_pack_directory
      directory = if defined?(Rails)
        Rails.root.join("db/seeds/english_arcade").to_s
      end
      return {} if directory.to_s.empty? || !Dir.exist?(directory)

      if defined?(EnglishArcade::PackLoader)
        begin
          return validated_packs(EnglishArcade::PackLoader.new(directory).load_all(validate: false, strict: false))
        rescue StandardError
          # PackLoader intentionally enforces the complete target list. During
          # a staggered content handoff, read the files that do exist below.
        end
      end

      packs = Dir.glob(File.join(directory, "*.yml")).each_with_object({}) do |path, result|
        target = File.basename(path, ".yml").tr("-", "_")
        begin
          result[target] = YAML.safe_load_file(path, aliases: false)
        rescue StandardError
          # A malformed or half-written pack must not hide the valid packs
          # beside it. The invalid target remains unavailable after the
          # per-file pass; production never fills it from a fixture.
        end
      end
      validated_packs(packs)
    end

    def self.load_contract_fixture
      return {} unless defined?(Rails)

      path = Rails.root.join("test/english_arcade/fixtures/english_c2_arcade.yml")
      return {} unless path.file?

      validated_packs(YAML.safe_load_file(path, aliases: true).fetch("targets", []).index_by { |target| target.fetch("key") })
    end

    def self.validated_packs(packs)
      packs.to_h.each_with_object({}) do |(target, pack), valid|
        validator = EnglishArcade::PackValidator.new(pack, strict: true)
        valid[target] = pack if validator.valid?
      rescue StandardError
        # A malformed target is unavailable to the runtime. Evidence-bound
        # content must never degrade into a blank or generic card.
      end
    end
    private_class_method :validated_packs

    def self.complete?(packs)
      targets = EnglishArcadeSessionBuilder::TARGETS.keys - %w[mixed interview]
      packs.is_a?(Hash) && targets.all? { |target| packs.key?(target) && Array(packs[target]["items"]).any? }
    end

    def self.merge_packs(packs, fixture, allow_fixture_fallback: false)
      canonical_targets = EnglishArcadeSessionBuilder::TARGETS.keys - %w[mixed interview]
      canonical_targets.each_with_object({}) do |target, result|
        pack = packs.is_a?(Hash) ? packs[target] : nil
        fallback = fixture.is_a?(Hash) ? fixture[target] : nil
        result[target] = pack if pack.is_a?(Hash) && Array(pack["items"]).any?
        # No generic fixture may fill a canonical production target. This
        # branch is reserved for an elective pack during a cold checkout.
        if allow_fixture_fallback && !EnglishArcade::Schema::CANONICAL_TARGETS.include?(target)
          result[target] ||= fallback if fallback.is_a?(Hash) && Array(fallback["items"]).any?
        end
      end
    end

    def self.source_for(packs, fixture)
      has_packs = packs.is_a?(Hash) && packs.any? { |_target, pack| Array(pack["items"]).any? }
      has_fixture = fixture.is_a?(Hash) && fixture.any? { |_target, pack| Array(pack["items"]).any? }
      return "english-arcade-packs" if complete?(packs)
      return "english-arcade-packs+contract-fixture" if has_packs && has_fixture
      return "english-arcade-packs" if has_packs

      "english-arcade-contract-fixture"
    end

    def initialize(packs, source_name:)
      @packs = packs
      @source_name = source_name
    end

    def cards_for(target)
      pack = @packs[target]
      if !pack.is_a?(Hash) || !Array(pack["items"]).any?
        return [] if EnglishArcade::Schema::CANONICAL_TARGETS.include?(target)

        return FixtureAdapter.cards_for(target)
      end

      normalized = Array(pack["items"]).map.with_index { |item, index| normalize_item(item, target, index) }
      if EnglishArcade::Schema::CANONICAL_INTERVIEW_CONTENT_TARGETS.include?(target) && normalized.any?(&:nil?)
        return []
      end

      normalized.compact
    end

    private

    def normalize_item(item, target, index)
      variants = EnglishArcadeAttemptContract.variants_for(item)
      initial = variants["initial"]
      return nil unless initial.is_a?(Hash)
      materialized = EnglishArcadeAttemptContract.materialize(initial, session_id: "preview", card_key: item["id"].to_s)
      feedback = stringify(item["feedback"] || {})
      rephrase = item["rephrase"].is_a?(Hash) ? item["rephrase"]["prompt"] : item["rephrase"]
      extension = item["extension"].is_a?(Hash) ? item["extension"]["prompt"] : item["extension"]
      follow_up = item["follow_up"].is_a?(Hash) ? item["follow_up"]["prompt"] : item["follow_up"]
      compression = item["compression"].is_a?(Hash) ? item["compression"]["prompt"] : item["compression"]
      if EnglishArcade::Schema::CANONICAL_INTERVIEW_CONTENT_TARGETS.include?(target)
        return nil unless item["follow_up"].is_a?(Hash) && follow_up.is_a?(String) && !follow_up.strip.empty?
        return nil unless item["compression"].is_a?(Hash) && compression.is_a?(String) && !compression.strip.empty?
        return nil unless variants["follow_up"].is_a?(Hash) && variants["delayed_variant"].is_a?(Hash)
      end
      sources = normalize_sources(item["sources"] || item["source"])
      provenance = normalize_provenance(item["provenance"])
      if EnglishArcade::Schema::PROVENANCE_REQUIRED_TARGETS.include?(target) && !complete_provenance?(sources, provenance)
        return nil
      end
      source = sources.first || item["source_ref"] || @source_name
      source = source["path"] if source.is_a?(Hash) && source["path"].present?

      {
        key: item["id"].to_s.presence || "#{target}-#{index + 1}",
        target: target,
        prompt: item["prompt"].to_s,
        context: item["context"].to_s,
        choices: materialized.fetch("options").map { |option| { "id" => option.fetch("id"), "text" => option.fetch("text") } },
        correct_choice: materialized.fetch("correct_choice"),
        answer_text: initial.fetch("best_answer").to_s,
        feedback: feedback,
        rephrase_prompt: rephrase.to_s,
        extension_prompt: extension.to_s.presence || "Extend the answer with one failure mode, metric, or verification step.",
        follow_up_prompt: follow_up.to_s.presence,
        compression_prompt: compression.to_s.presence,
        feynman: stringify(item["feynman"] || {}),
        black_box: stringify(item["black_box"] || {}),
        recall: stringify(item["recall"] || {}),
        tags: [ item["topic"], *Array(item["language_focus"]), target ].compact.map(&:to_s),
        source: source,
        sources: sources,
        provenance: provenance,
        variants: variants,
        # Keep the authored response ladder on the private raw-card contract.
        # ContentPackAdapter#cards_for is also used as a low-level projection
        # by contract tests and callers; exposing a new public key there would
        # blur the boundary between authored content and the runtime Card DTO.
        _response_versions: stringify(item["response_versions"] || {}),
        content_version: EnglishArcadeAttemptContract.content_version(item)
      }
    end

    def stringify(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested), result|
          result[key.to_s] = stringify(nested)
        end
      when Array
        value.map { |nested| stringify(nested) }
      else
        value
      end
    end

    def normalize_sources(value)
      values = value.is_a?(Array) ? value : [ value ]
      values.filter_map do |source|
        next if source.blank?

        source.is_a?(Hash) ? stringify(source) : source.to_s
      end
    end

    def normalize_provenance(value)
      raw = stringify(value)
      return {} unless raw.is_a?(Hash)

      provenance = PROVENANCE_KEYS.each_with_object({}) do |key, result|
        result[key] = raw[key] if raw.key?(key)
      end
      if provenance["files"].is_a?(Array)
        provenance["files"] = provenance["files"].filter_map do |file|
          next unless file.is_a?(Hash)

          PROVENANCE_FILE_KEYS.each_with_object({}) do |key, result|
            result[key] = file[key] if file.key?(key)
          end
        end
      end
      if provenance["confidentiality"].is_a?(Hash)
        provenance["confidentiality"] = CONFIDENTIALITY_KEYS.each_with_object({}) do |key, result|
          result[key] = provenance["confidentiality"][key] if provenance["confidentiality"].key?(key)
        end
      end
      provenance
    end

    def complete_provenance?(sources, provenance)
      return false unless sources.any? && sources.all? { |source| source.is_a?(Hash) }
      return false unless PROVENANCE_KEYS.all? { |key| provenance.key?(key) && provenance[key].present? }
      return false unless provenance["files"].is_a?(Array) && provenance["files"].any?
      return false unless provenance["files"].all? { |file| PROVENANCE_FILE_KEYS.all? { |key| file[key].present? } }

      confidentiality = provenance["confidentiality"]
      confidentiality.is_a?(Hash) && CONFIDENTIALITY_KEYS.all? { |key| confidentiality[key].present? }
    end
  end

  attr_reader :content

  def initialize(content: nil, clock: -> { Time.current })
    @content = content || ContentPackAdapter.build || FixtureAdapter
    @clock = clock
  end

  def targets
    TARGETS
  end

  def modes
    MODES
  end

  def thirty_day_plan
    EnglishArcadeCurriculum.plan.map(&:deep_dup)
  end

  def normalize_target(value)
    target = value.to_s.downcase.strip
    target = TARGET_ALIASES.fetch(target, target)
    return target if TARGETS.key?(target)

    "mixed"
  end

  def normalize_mode(value)
    mode = value.to_s.downcase.strip
    MODES.key?(mode) ? mode : "daily"
  end

  def call(target:, mode: "daily", learner_key: "anonymous", session: nil, limit: 5, persist_schedules: nil, on: @clock.call.to_date)
    target = normalize_target(target)
    mode = normalize_mode(mode)
    persist_schedules = !guided_session?(session) if persist_schedules.nil?
    required_keys = Array(session&.metadata&.fetch("required_card_keys", []))
    deck_seed = session&.metadata&.fetch("deck_seed", nil).to_s.presence
    cards = if target == "interview" && required_keys.empty?
      EnglishArcadeResumeInterviewProfile.cards(@content.cards_for("career"))
    else
      cards_for(target)
    end
    cards = required_keys.filter_map { |key| cards.find { |card| card.fetch(:key) == key } } if required_keys.any?
    attempts = session&.english_arcade_attempts&.pluck(:card_key) || []
    completed_required_keys = session&.english_arcade_attempts&.where(feedback_revealed: true, state: REQUIRED_MOCK_COMPLETED_STATES)&.to_a&.select { |attempt| attempt.correct? || attempt.black_box_complete? }&.map(&:card_key) || []
    attempted_keys = attempts.to_set
    variant_id = variant_id_for(session&.metadata&.fetch("exercise", "initial"))
    mock_id = session&.metadata&.fetch("mock_id", nil).to_s.presence
    mock_sequence = mock_id && Array(EnglishArcadeCurriculum.mock(mock_id)&.fetch("required_sequence", []))
    if required_keys.any? && mock_sequence
      expected_step = mock_sequence.fetch(attempts.length, nil)
      if expected_step
        expected_key = expected_step.fetch("card_key")
        cards = cards.select { |card| card.fetch(:key).to_s == expected_key.to_s }
        variant_id = expected_step["content_variant_id"].presence || expected_step.fetch("variant_id")
      else
        cards = []
      end
    elsif required_keys.any?
      # Preserve the legacy ordered General flow for links created before
      # curriculum-owned mock ids existed.
      cards = cards.reject { |card| completed_required_keys.include?(card.fetch(:key)) }
    end

    schedules = schedules_for(cards, learner_key: learner_key, on: on, persist: persist_schedules)
    interleaved = %w[mixed interview].include?(target)
    ordered = if required_keys.any?
      cards
    else
      cards.each_with_index.sort_by do |card, index|
        card_key = card.fetch(:key)
        schedule = schedules.fetch(card_key)
        deck_rank = deck_seed ? Digest::SHA256.hexdigest("#{deck_seed}:#{card_key}") : card_key
        tie_breakers = if deck_seed
          [ deck_rank ]
        else
          [ schedule.due_on, interleaved ? index % canonical_target_keys.length : 0, card_key ]
        end
        [ attempted_keys.include?(card_key) ? 1 : 0, schedule.due? ? 0 : 1, *tie_breakers ]
      end.map(&:first)
    end

    Plan.new(
      target: target,
      target_label: TARGETS.fetch(target)[:label],
      mode: mode,
      mode_label: MODES.fetch(mode)[:label],
      duration_seconds: MODES.fetch(mode)[:duration_seconds],
      cards: ordered.first(limit).map { |raw| card_from(raw, session: session, variant_id: variant_id) },
      source: source_name
    )
  end

  def cards_for(target)
    if target.to_s == "interview"
      resume_cards = EnglishArcadeResumeInterviewProfile.cards(@content.cards_for("career"))
      resume_keys = resume_cards.to_set { |card| card.fetch(:key) }
      canonical_cards = canonical_target_keys.flat_map { |key| @content.cards_for(key) }
      return resume_cards + canonical_cards.reject { |card| resume_keys.include?(card.fetch(:key)) }
    end

    targets = target.to_s == "mixed" ? canonical_target_keys : [ normalize_target(target) ]
    targets.flat_map { |key| @content.cards_for(key) }
  end

  def card_for(target:, card_key:, session: nil, variant_id: nil)
    raw = cards_for(target).find { |candidate| candidate.fetch(:key).to_s == card_key.to_s }
    raw && card_from(raw, session: session, variant_id: variant_id || variant_id_for(session&.metadata&.fetch("exercise", "initial")))
  end

  # The persisted attempt kind is a workflow label. The content contract owns
  # the actual prompt variant so that retry is a delayed variant while a
  # follow-up has its own authored question and answer.
  def variant_id_for(exercise)
    case exercise.to_s
    when "retry" then "delayed_variant"
    when "follow_up" then "follow_up"
    when "rephrase" then "rephrase"
    when "compression" then "compression"
    when "extension" then "extension"
    else "initial"
    end
  end

  def grade(card:, answer_choice:, typed_answer: nil)
    result = EnglishArcadeAttemptContract.grade(
      card.variant_contract,
      answer_choice: answer_choice,
      typed_answer: typed_answer
    )
    selected_option = result["selected_option"]
    diagnostic = {
      "target" => card.target,
      "card_key" => card.key,
      "tags" => card.tags,
      "selected_choice" => result["selected_choice"],
      "selected_option" => selected_option,
      "correct" => result["correct"],
      "typed_present" => typed_answer.to_s.strip.present?,
      "signal" => result["correct"] ? "answer-within-contract" : "needs-black-box-post-mortem",
      "assessment" => result.fetch("contract").merge(
        "correct" => result.fetch("correct"),
        "variant_id" => card.variant_id,
        "variant_digest" => card.variant_digest,
        "content_version" => card.content_version
      )
    }
    feedback = card.feedback.merge(
      "answer" => result["answer_text"],
      "selected" => selected_option,
      "typed_capture" => typed_answer.to_s.strip.presence,
      # The builder's direct Grade object is an internal reveal candidate. The
      # controller persists only diagnostic_evidence before Feynman, so these
      # fields cannot enter the closed prompt or pre-reveal JSON.
      "sources" => card.sources,
      "provenance" => card.provenance
    )
    Grade.new(correct: result.fetch("correct"), feedback: feedback, diagnostic_evidence: diagnostic)
  rescue EnglishArcadeAttemptContract::InvalidChoice
    raise
  end

  def prompt_snapshot(card)
    EnglishArcadeAttemptContract.snapshot(card.variant_contract, content_version: card.content_version).merge(
      "key" => card.key,
      "target" => card.target,
      "target_label" => card.target_label
    )
  end

  # Rehydrates only the committed public prompt for a pending Feynman pass.
  # The pack may be edited or reloaded between commit and reveal; the learner
  # must still see the exact question/options that produced the server grade.
  def frozen_card_for_attempt(attempt, session:)
    assessment = attempt.diagnostic_evidence.to_h.fetch("assessment", {}).to_h
    snapshot = attempt.prompt_snapshot.to_h
    current = card_for(
      target: attempt.target,
      card_key: attempt.card_key,
      session: session,
      variant_id: attempt.variant_key
    )
    return current unless snapshot["prompt"].present? && snapshot["options"].is_a?(Array)

    base = current || Card.new(
      key: attempt.card_key,
      target: attempt.target,
      target_label: TARGETS.fetch(attempt.target.to_s, { label: attempt.target.to_s }).fetch(:label),
      rephrase_prompt: nil,
      extension_prompt: nil,
      follow_up_prompt: nil,
      compression_prompt: nil,
      black_box: {},
      recall: {},
      tags: [ attempt.target.to_s ],
      source: nil,
      sources: [],
      provenance: {},
      variants: {},
      variant_contract: {},
      critical_thinking: {},
      response_versions: {},
      option_guides: {},
      content_version: snapshot["content_version"].to_s
    )

    base.dup.tap do |card|
      card.prompt = snapshot["prompt"].to_s
      card.context = snapshot["context"].to_s
      card.options = snapshot["options"].map { |choice| Choice.new(id: choice.fetch("id"), text: choice.fetch("text")) }
      card.correct_choice = assessment["correct_choice"].to_s
      card.answer_text = assessment["answer_text"].to_s
      card.feedback = assessment["feedback"].is_a?(Hash) ? assessment["feedback"] : card.feedback
      card.variant_id = snapshot["variant_id"].to_s
      card.variant_digest = snapshot["variant_digest"].to_s
      card.content_version = snapshot["content_version"].to_s
      card.feynman = assessment["check"].is_a?(Hash) ? assessment["check"] : card.feynman
      card.critical_thinking = assessment["critical_thinking"].is_a?(Hash) ? assessment["critical_thinking"] : card.critical_thinking
      card.response_versions = {}
      card.option_guides = {}
      card.variant_contract = card.variant_contract.merge(
        "id" => card.variant_id,
        "digest" => card.variant_digest,
        "prompt" => card.prompt,
        "context" => card.context,
        "best_answer" => card.answer_text,
        "feedback" => card.feedback,
        "check" => card.feynman,
        "critical_thinking" => card.critical_thinking,
        "options" => snapshot.fetch("options").map { |choice| choice.slice("id", "text") },
        "correct_choice" => card.correct_choice,
        "content_version" => card.content_version
      )
    end
  end

  def schedule_for(card:, learner_key:, on: @clock.call.to_date)
    EnglishArcadeCard.find_or_initialize_by(
      learner_key: learner_key,
      target: card.target,
      card_key: card.key
    ).tap do |schedule|
      schedule.due_on ||= on
      schedule.interval_days ||= EnglishArcadeCard::BOX_INTERVALS.fetch(schedule.box || 1)
      schedule.box ||= 1
      schedule.save! if schedule.new_record? || schedule.changed?
    end
  end

  private

  def guided_session?(session)
    session && session.metadata.to_h.deep_stringify_keys["experience"].to_s.downcase.strip == "guided"
  end

  def card_from(raw, session: nil, variant_id: "initial")
    metadata = TARGETS.fetch(raw.fetch(:target))
    raw_sources = raw[:sources]
    source_value = raw[:source] || (raw_sources.is_a?(Array) ? raw_sources.first : raw_sources)
    source_value = source_value["path"] if source_value.is_a?(Hash) && source_value["path"].present?
    sources = if raw_sources.is_a?(Array)
      raw_sources
    elsif raw_sources.present?
      [ raw_sources ]
    elsif raw[:source].present?
      [ raw[:source] ]
    else
      []
    end
    variants = raw.fetch(:variants, {})
    variants = fixture_variants(raw) if variants.blank?
    selected_variant_id = variant_id.to_s.presence || "initial"
    selected_variant = variants[selected_variant_id]
    if selected_variant.nil? && EnglishArcade::Schema::CANONICAL_TARGETS.include?(raw.fetch(:target).to_s)
      return nil
    end
    selected_variant ||= variants["initial"]
    selected_variant_id = selected_variant.fetch("id")
    session_id = session&.id || "preview"
    materialized = EnglishArcadeAttemptContract.materialize(
      selected_variant,
      session_id: session_id.to_s,
      card_key: raw.fetch(:key).to_s
    ).merge("content_version" => raw.fetch(:content_version, "unknown").to_s)
    selected_options = materialized.fetch("options").map { |choice| Choice.new(id: choice.fetch("id"), text: choice.fetch("text")) }
    # Response versions belong to the initial authored item. Adaptive variants
    # have their own best answer and must not inherit a misleading answer
    # ladder from the base prompt. Do not synthesize missing short/deep copy.
    response_versions = if selected_variant_id == "initial"
      raw.fetch(:_response_versions, raw.fetch(:response_versions, {})).to_h
    else
      {}
    end
    Card.new(
      key: raw.fetch(:key),
      target: raw.fetch(:target),
      target_label: metadata[:label],
      prompt: materialized.fetch("prompt"),
      context: materialized.fetch("context"),
      options: selected_options,
      correct_choice: materialized.fetch("correct_choice"),
      answer_text: materialized.fetch("best_answer"),
      feedback: materialized.fetch("feedback"),
      rephrase_prompt: raw.fetch(:rephrase_prompt),
      extension_prompt: raw.fetch(:extension_prompt),
      follow_up_prompt: raw.fetch(:follow_up_prompt),
      compression_prompt: raw.fetch(:compression_prompt),
      # The active variant owns its Feynman/check contract. Keeping this on
      # the materialized card prevents a follow-up from silently reusing the
      # base question's check while its own prompt/options are displayed.
      feynman: materialized.fetch("check", raw.fetch(:feynman, {})),
      black_box: raw.fetch(:black_box, {}),
      recall: raw.fetch(:recall, {}),
      tags: raw.fetch(:tags),
      source: source_value,
      sources: sources,
      provenance: raw.fetch(:provenance, {}),
      variants: variants,
      variant_id: selected_variant_id,
      variant_digest: materialized.fetch("digest"),
      variant_contract: materialized,
      critical_thinking: materialized.fetch("critical_thinking", {}),
      response_versions: response_versions,
      option_guides: option_guides_for(materialized, selected_variant),
      content_version: materialized.fetch("content_version")
    )
  end

  def option_guides_for(materialized, selected_variant)
    distractors = Array(selected_variant["distractors"]).filter_map do |entry|
      entry.is_a?(Hash) ? entry.deep_stringify_keys : nil
    end

    materialized.fetch("options").to_h do |option|
      best = option.fetch("id") == materialized.fetch("correct_choice")
      authored = distractors.find { |entry| entry["text"].to_s == option.fetch("text") }
      [
        option.fetch("id"),
        {
          "best" => best,
          "trap" => authored&.fetch("trap", nil),
          "explanation" => authored&.fetch("why_wrong", nil)
        }.compact
      ]
    end
  end

  def schedules_for(cards, learner_key:, on:, persist: true)
    cards.each_with_object({}) do |card, result|
      result[card.fetch(:key)] = if persist
        schedule_for(card: card_from(card), learner_key: learner_key, on: on)
      else
        # Guided reading is non-assessing: sorting uses an ephemeral due card
        # so opening a deck cannot create or advance server-side SRS state.
        EnglishArcadeCard.new(
          learner_key: learner_key,
          target: card.fetch(:target),
          card_key: card.fetch(:key),
          due_on: on,
          box: 1,
          interval_days: EnglishArcadeCard::BOX_INTERVALS.fetch(1)
        )
      end
    end
  end

  def fixture_variants(raw)
    choices = Array(raw[:choices]).map { |choice| choice.respond_to?(:to_h) ? choice.to_h.stringify_keys : {} }
    correct_id = raw[:correct_choice].to_s
    best_answer = raw[:answer_text].to_s.presence || choices.find { |choice| choice["id"].to_s == correct_id }&.fetch("text", "")
    distractors = choices.reject { |choice| choice["id"].to_s == correct_id }.map do |choice|
      { "text" => choice["text"].to_s, "why_wrong" => "This fixture option does not satisfy the authored contract." }
    end
    {
      "initial" => {
        "id" => "initial",
        "prompt" => raw[:prompt].to_s,
        "context" => raw[:context].to_s,
        "best_answer" => best_answer,
        "distractors" => distractors,
        "feedback" => raw[:feedback] || {},
        "check" => raw[:feynman] || {},
        "critical_thinking" => raw[:critical_thinking] || {
          "comparison" => { "applicable" => false, "rejected_alternative" => "Fixture content has no authored comparison." }
        }
      }
    }
  end

  def source_name
    @content.respond_to?(:source_name) ? @content.source_name : "#{@content.name}-v1"
  end

  # Curriculum evolves independently from the launcher. Until its next pack
  # handoff lands, use the schema as the stable source of truth so mixed and
  # interview sessions still include every canonical experience target.
  def canonical_target_keys
    curriculum_targets = Array(EnglishArcadeCurriculum::CANONICAL_TARGETS)
    schema_targets = Array(EnglishArcade::Schema::CANONICAL_TARGETS)
    curriculum_targets == schema_targets ? curriculum_targets : schema_targets
  end
end
