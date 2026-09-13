# frozen_string_literal: true

require "digest"
require "json"
require_relative "english_arcade_session_builder"
require_relative "../../lib/english_arcade/corpus_index"
require_relative "../../lib/english_arcade/exercise_factory"

# Read-only bridge between the validated English Arcade packs and the Arena.
# Arena progress is intentionally kept in its own tables; this object only
# materializes the already-gated content exposed by SessionBuilder.
class ArcadeContent
  CORE_STAGES = %w[meet recognize trap cloze rebuild produce speak transfer compress feynman].freeze
  INTERVIEW_PRACTICE_STAGES = EnglishArcadeResumeInterviewProfile::PRACTICE_STAGES
  FORBIDDEN_KEYS = %w[
    reveal best_answer correct correct_choice why_wrong pt_help sources provenance
    critical_thinking black_box variants response_versions answer recall_check
  ].freeze

  attr_reader :builder, :items, :index

  def initialize(builder: nil)
    @builder = builder || EnglishArcadeSessionBuilder.new
    @items = @builder.cards_for("mixed").compact.map { |item| factory_item(item) }.freeze
    @elective_items = EnglishArcade::Schema::ELECTIVE_TARGETS.flat_map do |target|
      @builder.cards_for(target).compact.map { |item| factory_item(item) }
    end.freeze
    @interview_items = EnglishArcadeResumeInterviewProfile.role_cards(@builder.cards_for("career")).map { |item| factory_item(item) }.freeze
    @lookup_items = (@items + @elective_items).uniq { |item| item.fetch("id").to_s }.freeze
    @index = EnglishArcade::CorpusIndex.new(@lookup_items)
    @factory = EnglishArcade::ExerciseFactory.new(corpus_index: @index)
  end

  def targets
    EnglishArcade::Schema::TARGETS
  end

  def items_for(target, interview_role: nil)
    target = normalize_target(target)
    source = if target == "mixed"
      @items
    elsif target == "interview"
      role = interview_role.to_s.presence
      return [] if role && !EnglishArcadeResumeInterviewProfile.interview_roles.include?(role)

      role ? @interview_items.select { |item| item.fetch("interview_role").to_s == role } : @interview_items
    else
      @builder.cards_for(target).compact.map { |item| factory_item(item) }
    end
    source
  end

  def item_for(target:, card_key:)
    items_for(target).find { |item| item.fetch(:key).to_s == card_key.to_s } ||
      @items.find { |item| item.fetch(:key).to_s == card_key.to_s }
  end

  def item_by_key(card_key)
    # Resume-role keys are isolated from canonical career IDs and checked
    # first. A persisted interview lesson must not silently materialize a
    # similarly named closed-book career card during show or grading.
    @interview_items.find { |item| item.fetch("id").to_s == card_key.to_s } ||
      @lookup_items.find { |item| item.fetch("id").to_s == card_key.to_s }
  end

  def interview_item?(item)
    item && item["interview_role"].present?
  end

  def content_version(item)
    # Pack contract versions describe the schema, not an editorial revision.
    # Bind the lesson to its actual text so an edited answer cannot silently
    # replace the material a learner saw before submitting.
    Digest::SHA256.hexdigest(canonical_json(factory_item(item)))[0, 16]
  end

  def build(item, stage:, slot: 0, timed: false, boss: false, occurrence: nil)
    @factory.build(
      factory_item(item),
      stage: stage,
      slot: slot,
      content_version: content_version(item),
      timed: timed,
      boss: boss,
      occurrence: occurrence
    )
  end

  def supported?(item, stage:, slot: 0)
    return false unless item

    @factory.supported?(factory_item(item), stage: stage, slot: slot)
  end

  def learner_exercise(item, stage:, slot: 0, timed: false, boss: false, occurrence: nil, include_model: false)
    exercise = sanitize(build(item, stage: stage, slot: slot, timed: timed, boss: boss, occurrence: occurrence))
    if include_model && %w[meet speak].include?(exercise["stage"].to_s)
      # The model is deliberately opt-in and only used for the active
      # Meet/Speak card. Future exercises never receive this field.
      exercise.fetch("payload")["model_text"] = factory_item(item).fetch("best_answer").to_s
    end
    if include_model && exercise["stage"].to_s == "meet" && interview_item?(factory_item(item))
      exercise.fetch("payload")["learning"] = stringify(factory_item(item)["learning"] || {})
    end
    exercise
  end

  def reveal(item, exercise:, grade: {}, response: nil, response_text: nil)
    exercise = stringify(exercise)
    grade = stringify(grade)
    selected_text = selected_text_for(exercise, response, response_text)
    selected_texts = selected_texts_for(exercise, response, response_text)
    variant_key = exercise.fetch("type", "") == "transfer" ? exercise.dig("payload", "variant") : nil
    reveal = @factory.reveal(factory_item(item), selected_text: selected_text, selected_texts: selected_texts, variant_key: variant_key)
    details = grade.fetch("details", {})
    reveal = stringify(reveal).merge("details" => details) unless details.empty?
    if exercise.fetch("type", "") == "cloze" && grade["correct"] == false && reveal["why_wrong"].to_s.empty?
      axis = grade["trap_axis"].to_s.strip
      reveal["why_wrong"] = axis.empty? ? "Recheck the marked blank." : "Recheck the marked blank for the #{axis} distinction."
    end
    reveal["correct"] = !!grade["correct"]
    reveal["rating"] = grade["rating"].to_i
    reveal["trap_axis"] = grade["trap_axis"] if grade.key?("trap_axis")
    if interview_item?(factory_item(item))
      learning = stringify(factory_item(item)["learning"] || {})
      reveal["learning"] = learning if learning.present?
      claims = Array(factory_item(item).dig("provenance", "verified_claims")).map(&:to_s).reject(&:blank?)
      reveal["evidence"] = {
        "claim_boundary" => "Resume-derived claims only; clarify details the supplied resumes do not establish.",
        "verified_claims" => claims
      } if claims.any?
    end
    reveal.compact
  end

  def sanitize(value)
    case value
    when Hash
      value.each_with_object({}) do |(key, nested), result|
        key_string = key.to_s
        next if FORBIDDEN_KEYS.include?(key_string.downcase)

        result[key_string] = sanitize(nested)
      end
    when Array
      value.map { |nested| sanitize(nested) }
    else
      value
    end
  end

  def normalize_target(value)
    @builder.normalize_target(value)
  end

  private

  # SessionBuilder intentionally returns a learner-facing Card-shaped hash for
  # the legacy assessment. The pure Arena modules consume the authored item
  # contract instead. Adapt once here so both paths keep the same validated
  # loader/gate and no second YAML reader is introduced.
  def factory_item(item)
    item = stringify(item)
    return item if item["id"].to_s.present? && item["best_answer"].to_s.present? && item["distractors"].is_a?(Array)

    variants = stringify(item["variants"] || {})
    initial = stringify(variants["initial"] || {})
    contract = item.merge(
      "id" => item["key"].to_s,
      "version" => item["content_version"].to_s.presence || "1.0.0",
      "best_answer" => initial["best_answer"].to_s,
      "distractors" => Array(initial["distractors"]),
      "feedback" => stringify(item["feedback"] || initial["feedback"] || {}),
      "follow_up" => variants["follow_up"],
      "delayed_variant" => variants["delayed_variant"],
      "compression" => item["compression"] || { "prompt" => item["compression_prompt"].to_s }
    )
    contract.merge(
      key: contract["id"],
      target: contract["target"],
      prompt: contract["prompt"],
      context: contract["context"],
      version: contract["version"],
      best_answer: contract["best_answer"],
      distractors: contract["distractors"],
      feedback: contract["feedback"],
      variants: variants,
      recall: contract["recall"] || {},
      feynman: contract["feynman"] || {},
      content_version: contract["content_version"] || contract["version"]
    )
  end

  def selected_text_for(exercise, response, response_text)
    payload = exercise.fetch("payload", {})
    case exercise.fetch("type", "")
    when "choose_best", "transfer"
      Array(payload["options"]).find { |option| option["id"].to_s == response.to_s }&.fetch("text", nil)
    when "trap_axis"
      payload["distractor"]
    when "cloze"
      selected_texts_for(exercise, response, response_text).join(" ")
    else
      response_text
    end
  end

  def selected_texts_for(exercise, response, response_text)
    return [ response_text ] unless exercise.fetch("type", "") == "cloze"

    submitted = response.is_a?(Hash) ? stringify(response) : {}
    Array(exercise.dig("payload", "blanks")).filter_map do |blank|
      value = submitted[blank.fetch("id")].to_s.strip
      value unless value.empty?
    end
  end

  def canonical_json(value)
    JSON.generate(sort_hash(value))
  end

  def sort_hash(value)
    case value
    when Hash
      value.to_h.sort_by { |key, _| key.to_s }.to_h { |key, nested| [ key.to_s, sort_hash(nested) ] }
    when Array then value.map { |nested| sort_hash(nested) }
    else value
    end
  end

  def stringify(value)
    case value
    when Hash then value.each_with_object({}) { |(key, nested), result| result[key.to_s] = stringify(nested) }
    when Array then value.map { |nested| stringify(nested) }
    else value
    end
  end
end
