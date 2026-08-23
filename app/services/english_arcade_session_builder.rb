# Builds the closed-book English interview loop without embedding the standalone
# Vite app. The fixture adapter is deliberately replaceable: an Opus/content
# provider can implement `cards_for(target)` and be injected at boot or in a
# test without changing the session, grading, or scheduling contract.
require "digest"
require "set"
require "yaml"

class EnglishArcadeSessionBuilder
  TARGETS = {
    "dsa" => { label: "DSA & algorithms", short_label: "DSA", focus: "patterns, invariants, complexity, and Ruby traps" },
    "ruby" => { label: "Ruby", short_label: "Ruby", focus: "object model, blocks, performance, and concurrency" },
    "rails" => { label: "Ruby on Rails", short_label: "Rails", focus: "request flow, data access, jobs, caching, and security" },
    "react" => { label: "React", short_label: "React", focus: "rendering, state, effects, fetching, and accessibility" },
    "golang" => { label: "Golang", short_label: "Go", focus: "interfaces, goroutines, context, errors, and profiling" },
    "elixir" => { label: "Elixir", short_label: "Elixir", focus: "processes, OTP, back-pressure, and fault tolerance" },
    "salesforce" => { label: "Salesforce", short_label: "Salesforce", focus: "governor limits, Apex, Flow, integration, and security" },
    "system_design" => { label: "System design", short_label: "System design", focus: "requirements, capacity, source of truth, and failure trade-offs" },
    "mixed" => { label: "Mixed practice", short_label: "Mixed", focus: "interleaved interview decisions across every target" },
    "interview" => { label: "Interview mode", short_label: "Interview", focus: "closed-book answers with follow-ups and pragmatic phrasing" }
  }.freeze

  MODES = {
    "daily" => { label: "Daily drill", duration_seconds: 600 },
    "timed_45" => { label: "45-minute interview", duration_seconds: 45.minutes.to_i }
  }.freeze

  # The 30-day path is a practice calendar, not a CEFR promise. Each day has
  # one observable goal, cumulative review/interleaving, and a weak-area repair
  # loop. Full mocks are explicit so the launcher and exports can report them.
  DAILY_GOALS = [
    "Baseline closed-book recall across every target and record the first weak signal.",
    "State DSA invariants before implementation and test one counterexample.",
    "Defend DSA complexity with workload assumptions and an observable metric.",
    "Explain Ruby object boundaries with one precise class and value-object example.",
    "Compare Ruby allocation, laziness, and concurrency trade-offs without absolutes.",
    "Trace a Rails request and name the data, authorization, and failure boundaries.",
    "Defend Rails query shape, retries, caching, and security with evidence.",
    "Separate React render purity, state ownership, and accessible interaction.",
    "Explain React effects and fetch races, then name the user-visible recovery.",
    "Name Go interface ownership, goroutine lifetime, and the first profiling signal.",
    "Bound Go cancellation, error wrapping, and back-pressure at a service seam.",
    "Explain Elixir process isolation and run a full System Design mock.",
    "Use OTP supervision and recovery language for an observable failure mode.",
    "Respect Salesforce limits, sharing, and least privilege in a bulk-safe answer.",
    "Choose Salesforce Flow, Apex, or integration boundaries with a reversible test.",
    "Clarify System Design actors, capacity, source of truth, and success signals.",
    "Compare consistency, queues, retries, and failure modes without hiding costs.",
    "Interleave a mixed interview round and keep the answer-first C2 register.",
    "Rephrase technical answers for a stakeholder and add one measured extension.",
    "Run a full DSA mock with invariant, complexity, trace, and recovery language.",
    "Repair the lowest-scoring target with one targeted variant and a concrete signal.",
    "Run a full System Design mock from requirements through risks and rollback.",
    "Interleave three targets and alternate mechanism, policy, and evidence.",
    "Audit Feynman explanations and Black Box actions for specificity and dates.",
    "Connect Elixir and Salesforce failure isolation to real operational trade-offs.",
    "Connect React and Rails boundaries while keeping user impact explicit.",
    "Connect Go and Ruby concurrency reasoning to ownership and cancellation.",
    "Turn the weakest recurring signal into a small exercise and a retest date.",
    "Compress each answer to decision, caveat, evidence, and next step.",
    "Run full DSA and System Design mocks, then set the next 30-day weak-area loop."
  ].freeze

  MOCK_TARGETS_BY_DAY = {
    10 => %w[dsa],
    12 => %w[system_design],
    20 => %w[dsa],
    22 => %w[system_design],
    30 => %w[dsa system_design]
  }.freeze

  THIRTY_DAY_PLAN = DAILY_GOALS.each_with_index.map do |goal, index|
    day = index + 1
    previous_days = day - 1
    mocks = MOCK_TARGETS_BY_DAY.fetch(day, []).map do |target|
      {
        "target" => target,
        "mode" => "timed_45",
        "duration_seconds" => MODES.fetch("timed_45").fetch(:duration_seconds),
        "label" => "Full 45-minute #{TARGETS.fetch(target).fetch(:label)} mock"
      }.freeze
    end.freeze

    {
      "day" => day,
      "goal" => goal,
      "review" => previous_days.zero? ? "Baseline recall; begin the due-card log." : "Review due cards from days 1–#{previous_days} and interleave a second target.",
      "interleaving" => previous_days.zero? ? "Establish one-target baseline evidence." : "Pair today's focus with one due card from an earlier target.",
      "weak_area_remediation" => "Revisit the lowest-scoring target, write one actionable Black Box repair, and schedule a retest.",
      "mocks" => mocks
    }.freeze
  end.freeze

  TARGET_ALIASES = {
    "dsa & algorithms" => "dsa",
    "system design" => "system_design",
    "system-design" => "system_design",
    "mixed practice" => "mixed",
    "interview mode" => "interview",
    "go" => "golang"
  }.freeze

  Plan = Struct.new(
    :target, :target_label, :mode, :mode_label, :duration_seconds, :cards, :source,
    keyword_init: true
  )
  Choice = Struct.new(:id, :text, keyword_init: true)
  Card = Struct.new(
    :key, :target, :target_label, :prompt, :context, :options, :correct_choice,
    :answer_text, :feedback, :rephrase_prompt, :extension_prompt, :tags, :source,
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
      "salesforce" => "I would state the platform limit or security boundary first, then choose the smallest maintainable automation path.",
      "system_design" => "I would clarify the success metric and traffic shape first, then choose a source of truth and name the failure trade-off."
    }.freeze

    DISTRACTOR_TEMPLATES = [
      "I would jump straight to a library choice and leave the constraint implicit.",
      "I would promise that the happy path is enough and defer failure handling until production.",
      "I would give a universal rule without checking the workload, audience, or boundary."
    ].freeze

    def self.cards_for(target)
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
    attr_reader :source_name

    def self.build
      packs = load_pack_directory
      fixture = load_contract_fixture

      # A content handoff can land target packs independently. Prefer each
      # available canonical pack, then fill only the missing targets from the
      # stable contract fixture. This keeps a partial Opus/content drop useful
      # without making the launcher fail closed for the remaining targets.
      merged = merge_packs(packs, fixture)
      return new(merged, source_name: source_for(packs, fixture)) if merged.any?

      nil
    rescue StandardError
      nil
    end

    def self.load_pack_directory
      directory = if defined?(Rails)
        Rails.root.join("db/seeds/english_arcade").to_s
      end
      return {} if directory.to_s.empty? || !Dir.exist?(directory)

      if defined?(EnglishArcade::PackLoader)
        begin
          return EnglishArcade::PackLoader.new(directory).load_all(validate: false, strict: false)
        rescue StandardError
          # PackLoader intentionally enforces the complete target list. During
          # a staggered content handoff, read the files that do exist below.
        end
      end

      Dir.glob(File.join(directory, "*.yml")).each_with_object({}) do |path, result|
        target = File.basename(path, ".yml").tr("-", "_")
        begin
          result[target] = YAML.safe_load_file(path, aliases: false)
        rescue StandardError
          # A malformed or half-written pack must not hide the valid packs
          # beside it; the merge step supplies the contract fixture for this
          # target until content validation is repaired.
        end
      end
    end

    def self.load_contract_fixture
      return {} unless defined?(Rails)

      path = Rails.root.join("test/english_arcade/fixtures/english_c2_arcade.yml")
      return {} unless path.file?

      YAML.safe_load_file(path, aliases: true).fetch("targets", []).index_by { |target| target.fetch("key") }
    end

    def self.complete?(packs)
      targets = EnglishArcadeSessionBuilder::TARGETS.keys - %w[mixed interview]
      packs.is_a?(Hash) && targets.all? { |target| packs.key?(target) && Array(packs[target]["items"]).any? }
    end

    def self.merge_packs(packs, fixture)
      canonical_targets = EnglishArcadeSessionBuilder::TARGETS.keys - %w[mixed interview]
      canonical_targets.each_with_object({}) do |target, result|
        pack = packs.is_a?(Hash) ? packs[target] : nil
        fallback = fixture.is_a?(Hash) ? fixture[target] : nil
        result[target] = pack if pack.is_a?(Hash) && Array(pack["items"]).any?
        result[target] ||= fallback if fallback.is_a?(Hash) && Array(fallback["items"]).any?
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
      return FixtureAdapter.cards_for(target) unless pack.is_a?(Hash) && Array(pack["items"]).any?

      Array(pack["items"]).map.with_index { |item, index| normalize_item(item, target, index) }
    end

    private

    def normalize_item(item, target, index)
      answer = item["best_answer"] || item["answer"]
      distractors = Array(item["distractors"]).filter_map { |entry| entry.is_a?(Hash) ? entry["text"] : entry }
      choices = [ answer, *distractors ].first(4).map.with_index { |text, choice_index| { id: (("a".ord + choice_index).chr), text: text.to_s } }
      rotated = choices.rotate((index + target.length) % choices.length)
      feedback = stringify(item["feedback"] || {})
      rephrase = item["rephrase"].is_a?(Hash) ? item["rephrase"]["prompt"] : item["rephrase"]
      extension = item["extension"].is_a?(Hash) ? item["extension"]["prompt"] : item["extension"]
      source = item.dig("sources", 0, "path") || item["source_ref"] || @source_name

      {
        key: item["id"].to_s.presence || "#{target}-#{index + 1}",
        target: target,
        prompt: item["prompt"].to_s,
        context: item["context"].to_s,
        choices: rotated,
        correct_choice: rotated.first.fetch(:id),
        answer_text: answer.to_s,
        feedback: feedback,
        rephrase_prompt: rephrase.to_s,
        extension_prompt: extension.to_s,
        tags: [ item["topic"], *Array(item["language_focus"]), target ].compact.map(&:to_s),
        source: source.to_s
      }
    end

    def stringify(value)
      value.respond_to?(:to_h) ? value.to_h.transform_keys(&:to_s) : {}
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
    THIRTY_DAY_PLAN.map do |entry|
      entry.merge("mocks" => entry.fetch("mocks").map(&:dup))
    end
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

  def call(target:, mode: "daily", learner_key: "anonymous", session: nil, limit: 5, on: @clock.call.to_date)
    target = normalize_target(target)
    mode = normalize_mode(mode)
    cards = cards_for(target)
    attempts = session&.english_arcade_attempts&.pluck(:card_key) || []
    attempted_keys = attempts.to_set

    schedules = schedules_for(cards, learner_key: learner_key, on: on)
    interleaved = %w[mixed interview].include?(target)
    ordered = cards.each_with_index.sort_by do |card, index|
      card_key = card.fetch(:key)
      schedule = schedules.fetch(card_key)
      [ attempted_keys.include?(card_key) ? 1 : 0, schedule.due? ? 0 : 1, schedule.due_on, interleaved ? index % 8 : 0, card_key ]
    end.map(&:first)

    Plan.new(
      target: target,
      target_label: TARGETS.fetch(target)[:label],
      mode: mode,
      mode_label: MODES.fetch(mode)[:label],
      duration_seconds: MODES.fetch(mode)[:duration_seconds],
      cards: ordered.first(limit).map { |raw| card_from(raw) },
      source: source_name
    )
  end

  def cards_for(target)
    targets = %w[mixed interview].include?(target.to_s) ? TARGETS.keys - %w[mixed interview] : [ normalize_target(target) ]
    targets.flat_map { |key| @content.cards_for(key) }
  end

  def card_for(target:, card_key:)
    raw = cards_for(target).find { |candidate| candidate.fetch(:key).to_s == card_key.to_s }
    raw && card_from(raw)
  end

  def grade(card:, answer_choice:, typed_answer: nil, spoken_text: nil)
    selected = answer_choice.to_s.strip.downcase.presence
    correct = selected.present? && ActiveSupport::SecurityUtils.secure_compare(
      Digest::SHA256.hexdigest(selected), Digest::SHA256.hexdigest(card.correct_choice.to_s)
    )
    chosen_option = card.options.find { |choice| choice.id == selected }

    Grade.new(
      correct: correct,
      feedback: card.feedback.merge(
        "answer" => card.answer_text,
        "selected" => chosen_option&.text,
        "typed_capture" => typed_answer.to_s.strip.presence,
        "spoken_capture" => spoken_text.to_s.strip.presence
      ),
      diagnostic_evidence: {
        "target" => card.target,
        "card_key" => card.key,
        "tags" => card.tags,
        "selected_choice" => selected,
        "selected_option" => chosen_option&.text,
        "correct" => correct,
        "typed_present" => typed_answer.to_s.strip.present?,
        "spoken_present" => spoken_text.to_s.strip.present?,
        "signal" => correct ? "answer-within-contract" : "needs-black-box-post-mortem"
      }
    )
  end

  def prompt_snapshot(card)
    {
      "key" => card.key,
      "target" => card.target,
      "target_label" => card.target_label,
      "prompt" => card.prompt,
      "context" => card.context,
      "options" => card.options.map { |choice| { "id" => choice.id, "text" => choice.text } },
      "rephrase_prompt" => card.rephrase_prompt,
      "extension_prompt" => card.extension_prompt,
      "tags" => card.tags,
      "source" => card.source
    }
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

  def card_from(raw)
    metadata = TARGETS.fetch(raw.fetch(:target))
    Card.new(
      key: raw.fetch(:key),
      target: raw.fetch(:target),
      target_label: metadata[:label],
      prompt: raw.fetch(:prompt),
      context: raw.fetch(:context),
      options: raw.fetch(:choices).map { |choice| Choice.new(id: choice.fetch(:id), text: choice.fetch(:text)) },
      correct_choice: raw.fetch(:correct_choice),
      answer_text: raw.fetch(:answer_text),
      feedback: raw.fetch(:feedback),
      rephrase_prompt: raw.fetch(:rephrase_prompt),
      extension_prompt: raw.fetch(:extension_prompt),
      tags: raw.fetch(:tags),
      source: raw.fetch(:source)
    )
  end

  def schedules_for(cards, learner_key:, on:)
    cards.each_with_object({}) do |card, result|
      result[card.fetch(:key)] = schedule_for(card: card_from(card), learner_key: learner_key, on: on)
    end
  end

  def source_name
    @content.respond_to?(:source_name) ? @content.source_name : "#{@content.name}-v1"
  end
end
