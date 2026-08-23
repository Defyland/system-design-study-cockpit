# frozen_string_literal: true

require_relative "schema"

module EnglishArcade
  # Validates a single target pack against EnglishArcade::Schema.
  #
  # The validator is deliberately strict and deliberately boring: every rule
  # maps to a failure a learner would actually notice, such as a leaked answer,
  # a distractor nobody would ever pick, or feedback that says nothing.
  class PackValidator
    Error = Struct.new(:path, :message, keyword_init: true) do
      def to_s = "#{path}: #{message}"
    end

    attr_reader :errors, :warnings

    # strict: also treat publishable-bar shortfalls (fewer than 12 items) as
    # errors. Release runs strict; authoring runs lenient and reads warnings.
    def initialize(pack, strict: true)
      @pack = pack
      @strict = strict
      @errors = []
      @warnings = []
    end

    def self.validate!(pack, strict: true)
      validator = new(pack, strict: strict)
      return true if validator.valid?

      raise ArgumentError, "Invalid English Arcade pack:\n#{validator.errors.join("\n")}"
    end

    def valid?
      @errors = []
      @warnings = []
      validate_pack_shape
      return @errors.empty? if @errors.any?

      validate_target
      validate_templates
      validate_items
      validate_cards
      @errors.empty?
    end

    private

    def add(path, message)
      @errors << Error.new(path: path, message: message)
    end

    def warn(path, message)
      @warnings << Error.new(path: path, message: message)
    end

    # Publishable-bar findings: hard failures in strict mode, advisory while
    # authoring, so a half-written pack still reports its real content errors.
    def add_or_warn(path, message)
      @strict ? add(path, message) : warn(path, message)
    end

    def validate_pack_shape
      return add("pack", "must be a Hash") unless @pack.is_a?(Hash)

      add("pack.target", "missing target definition") unless @pack["target"].is_a?(Hash)
      add("pack.items", "missing items array") unless @pack["items"].is_a?(Array)
    end

    def target_key
      @pack.dig("target", "key")
    end

    def validate_target
      target = @pack["target"]

      Schema::REQUIRED_TARGET_KEYS.each do |key|
        add("target.#{key}", "is required") if blank?(target[key])
      end

      unless Schema.target?(target["key"])
        add("target.key", "#{target["key"].inspect} is not a known target")
      end

      focus = target["focus_areas"]
      if !focus.is_a?(Array) || focus.size < 3
        add("target.focus_areas", "must list at least 3 focus areas")
      end

      simulation = target["simulation"]
      if simulation.is_a?(Hash)
        add("target.simulation.minutes", "must be a positive integer") unless simulation["minutes"].is_a?(Integer) && simulation["minutes"].positive?
        add("target.simulation.structure", "must list the timed segments") unless simulation["structure"].is_a?(Array) && simulation["structure"].any?
      else
        add("target.simulation", "must be a Hash describing the timed session")
      end
    end

    def validate_templates
      templates = @pack["templates"] || []

      unless templates.is_a?(Array)
        add("templates", "must be an array")
        return
      end

      if Schema.template_required?(target_key) && templates.empty?
        add("templates", "target #{target_key} requires at least one answer template")
      end

      templates.each_with_index do |template, index|
        path = "templates[#{index}]"
        Schema::REQUIRED_TEMPLATE_KEYS.each do |key|
          add("#{path}.#{key}", "is required") if blank?(template[key])
        end

        steps = template["steps"]
        add("#{path}.steps", "must list at least 3 ordered steps") if !steps.is_a?(Array) || steps.size < 3
        validate_source("#{path}.source", template["source"]) if template["source"]
      end
    end

    def template_ids
      (@pack["templates"] || []).filter_map { |template| template["id"] }
    end

    def validate_items
      items = @pack["items"]
      return unless items.is_a?(Array)

      if items.size < Schema::MINIMUM_ITEMS_PER_TARGET
        add("items", "target #{target_key} has #{items.size} items, needs >= #{Schema::MINIMUM_ITEMS_PER_TARGET}")
      elsif items.size < Schema::PUBLISHABLE_ITEMS_PER_TARGET
        add_or_warn("items", "target #{target_key} has #{items.size} items, publishable bar is #{Schema::PUBLISHABLE_ITEMS_PER_TARGET}")
      end

      ids = items.filter_map { |item| item["id"] }
      duplicates = ids.tally.select { |_, count| count > 1 }.keys
      add("items", "duplicate item ids: #{duplicates.join(", ")}") if duplicates.any?

      items.each_with_index { |item, index| validate_item(item, "items[#{index}]") }
    end

    def validate_item(item, path)
      return add(path, "must be a Hash") unless item.is_a?(Hash)

      Schema::REQUIRED_ITEM_KEYS.each do |key|
        add("#{path}.#{key}", "is required") if blank?(item[key])
      end

      unknown = item.keys - Schema::REQUIRED_ITEM_KEYS - Schema::OPTIONAL_ITEM_KEYS
      add("#{path}", "unknown keys: #{unknown.join(", ")}") if unknown.any?

      validate_item_identity(item, path)
      validate_item_prose(item, path)
      validate_distractors(item, path)
      validate_feedback(item, path)
      validate_rephrase(item, path)
      validate_feynman(item, path)
      validate_black_box(item, path)
      validate_recall(item, path)
      validate_sources(item, path)
      validate_template_binding(item, path)
      validate_no_answer_leak(item, path)
    end

    def validate_item_identity(item, path)
      if item["target"] != target_key
        add("#{path}.target", "is #{item["target"].inspect} but pack target is #{target_key.inspect}")
      end

      id = item["id"]
      if id.is_a?(String) && !id.start_with?("#{target_key}-")
        add("#{path}.id", "must be prefixed with #{target_key}-")
      end

      version = item["version"]
      if version.is_a?(String) && !version.match?(Schema::ITEM_VERSION_FORMAT)
        add("#{path}.version", "#{version.inspect} must look like MAJOR.MINOR.PATCH")
      end

      unless Schema::DIFFICULTIES.include?(item["difficulty"])
        add("#{path}.difficulty", "must be one of #{Schema::DIFFICULTIES.to_a.join(", ")}")
      end

      unless Schema::INTERVIEW_STAGES.include?(item["interview_stage"])
        add("#{path}.interview_stage", "#{item["interview_stage"].inspect} is not a known stage")
      end
    end

    def validate_item_prose(item, path)
      check_length("#{path}.prompt", item["prompt"], Schema::MIN_LENGTHS["prompt"])
      check_length("#{path}.context", item["context"], Schema::MIN_LENGTHS["context"])
      check_length("#{path}.best_answer", item["best_answer"], Schema::MIN_LENGTHS["best_answer"])

      prompt = item["prompt"]
      if prompt.is_a?(String) && !spoken_interviewer_turn?(prompt)
        add("#{path}.prompt", "must read as a spoken interviewer turn")
      end
    end

    # Real interviewers ask questions, but they also give imperative turns such
    # as "Tell me about a time...". Both are natural; a statement is not.
    IMPERATIVE_OPENERS = %w[tell walk describe talk explain give show take].freeze

    def spoken_interviewer_turn?(prompt)
      return true if prompt.include?("?")

      first_word = prompt.strip.downcase.split(/[^a-z]+/).first
      IMPERATIVE_OPENERS.include?(first_word)
    end

    def validate_distractors(item, path)
      distractors = item["distractors"]
      unless distractors.is_a?(Array)
        return add("#{path}.distractors", "must be an array")
      end

      if distractors.size < Schema::MINIMUM_DISTRACTORS
        add("#{path}.distractors", "needs >= #{Schema::MINIMUM_DISTRACTORS} plausible distractors")
      end

      best = item["best_answer"]
      distractors.each_with_index do |distractor, index|
        dpath = "#{path}.distractors[#{index}]"
        unless distractor.is_a?(Hash)
          add(dpath, "must be a Hash")
          next
        end

        Schema::REQUIRED_DISTRACTOR_KEYS.each do |key|
          add("#{dpath}.#{key}", "is required") if blank?(distractor[key])
        end

        check_length("#{dpath}.text", distractor["text"], Schema::MIN_LENGTHS["distractor_text"])
        check_length("#{dpath}.why_wrong", distractor["why_wrong"], Schema::MIN_LENGTHS["why_wrong"])

        trap = distractor["trap"]
        if trap.is_a?(String) && !Schema::LANGUAGE_AXES.include?(trap) && trap != "content"
          add("#{dpath}.trap", "#{trap.inspect} must be a language axis or \"content\"")
        end

        if distractor["text"] == best
          add("#{dpath}.text", "duplicates the best answer")
        end
      end

      validate_length_tell(item, path, distractors)
    end

    # If the best answer is always far longer than every distractor, a learner
    # can score without reading. Reject that shape.
    def validate_length_tell(item, path, distractors)
      best = item["best_answer"]
      return unless best.is_a?(String)

      lengths = distractors.filter_map { |d| d["text"].is_a?(String) ? d["text"].length : nil }
      return if lengths.empty?

      if best.length > lengths.max * Schema::MAX_BEST_ANSWER_LENGTH_RATIO
        add("#{path}.best_answer", "is #{best.length} chars vs longest distractor #{lengths.max}; length alone reveals the answer")
      end
    end

    def validate_feedback(item, path)
      feedback = item["feedback"]
      unless feedback.is_a?(Hash)
        return add("#{path}.feedback", "must be a Hash keyed by language axis")
      end

      missing = Schema::LANGUAGE_AXES - feedback.keys
      add("#{path}.feedback", "missing axes: #{missing.join(", ")}") if missing.any?

      extra = feedback.keys - Schema::LANGUAGE_AXES
      add("#{path}.feedback", "unknown axes: #{extra.join(", ")}") if extra.any?

      feedback.each do |axis, text|
        check_length("#{path}.feedback.#{axis}", text, Schema::MIN_LENGTHS["feedback"])
      end
    end

    def validate_rephrase(item, path)
      rephrase = item["rephrase"]
      unless rephrase.is_a?(Hash)
        return add("#{path}.rephrase", "must be a Hash")
      end

      Schema::REQUIRED_REPHRASE_KEYS.each do |key|
        add("#{path}.rephrase.#{key}", "is required") if blank?(rephrase[key])
      end

      check_length("#{path}.rephrase.prompt", rephrase["prompt"], Schema::MIN_LENGTHS["rephrase_prompt"])
      check_length("#{path}.rephrase.goal", rephrase["goal"], Schema::MIN_LENGTHS["rephrase_goal"])
    end

    # Feynman keys are exact: the session engine renders them positionally.
    def validate_feynman(item, path)
      feynman = item["feynman"]
      unless feynman.is_a?(Hash)
        return add("#{path}.feynman", "must be a Hash")
      end

      missing = Schema::REQUIRED_FEYNMAN_KEYS - feynman.keys
      add("#{path}.feynman", "missing keys: #{missing.join(", ")}") if missing.any?

      extra = feynman.keys - Schema::REQUIRED_FEYNMAN_KEYS
      add("#{path}.feynman", "unknown keys: #{extra.join(", ")}") if extra.any?

      Schema::REQUIRED_FEYNMAN_KEYS.each do |key|
        check_length("#{path}.feynman.#{key}", feynman[key], Schema::MIN_LENGTHS["feynman_text"])
      end
    end

    # Black Box runs only after an error, and all five fields are required so
    # the post-mortem cannot degrade into a single vague sentence.
    def validate_black_box(item, path)
      black_box = item["black_box"]
      unless black_box.is_a?(Hash)
        return add("#{path}.black_box", "must be a Hash")
      end

      missing = Schema::REQUIRED_BLACK_BOX_KEYS - black_box.keys
      add("#{path}.black_box", "missing keys: #{missing.join(", ")}") if missing.any?

      extra = black_box.keys - Schema::REQUIRED_BLACK_BOX_KEYS
      add("#{path}.black_box", "unknown keys: #{extra.join(", ")}") if extra.any?

      Schema::REQUIRED_BLACK_BOX_KEYS.each do |key|
        check_length("#{path}.black_box.#{key}", black_box[key], Schema::MIN_LENGTHS["black_box_text"])
      end
    end

    def validate_cards
      cards = @pack["cards"]
      unless cards.is_a?(Array)
        return add("cards", "must be an array of production Leitner cards")
      end

      if cards.size < Schema::MINIMUM_CARDS_PER_TARGET || cards.size > Schema::MAXIMUM_CARDS_PER_TARGET
        add("cards", "target #{target_key} has #{cards.size} cards, expected #{Schema::MINIMUM_CARDS_PER_TARGET}-#{Schema::MAXIMUM_CARDS_PER_TARGET}")
      end

      ids = cards.filter_map { |card| card["id"] }
      duplicates = ids.tally.select { |_, count| count > 1 }.keys
      add("cards", "duplicate card ids: #{duplicates.join(", ")}") if duplicates.any?

      cards.each_with_index do |card, index|
        cpath = "cards[#{index}]"
        unless card.is_a?(Hash)
          add(cpath, "must be a Hash")
          next
        end

        Schema::REQUIRED_CARD_KEYS.each do |key|
          add("#{cpath}.#{key}", "is required") if blank?(card[key])
        end

        if card["id"].is_a?(String) && !card["id"].start_with?("#{target_key}-card-")
          add("#{cpath}.id", "must be prefixed with #{target_key}-card-")
        end

        check_length("#{cpath}.front", card["front"], Schema::MIN_LENGTHS["card_text"])
        check_length("#{cpath}.back", card["back"], Schema::MIN_LENGTHS["card_text"])

        unless Schema::LEITNER_BOXES.include?(card["box"])
          add("#{cpath}.box", "must be between 1 and 5")
        end

        validate_source("#{cpath}.source", card["source"])
      end
    end

    def validate_recall(item, path)
      recall = item["recall"]
      unless recall.is_a?(Hash)
        return add("#{path}.recall", "must be a Hash")
      end

      Schema::REQUIRED_RECALL_KEYS.each do |key|
        add("#{path}.recall.#{key}", "is required") if blank?(recall[key])
      end

      %w[active_recall_cue feynman_prompt black_box_probe].each do |key|
        check_length("#{path}.recall.#{key}", recall[key], Schema::MIN_LENGTHS["recall_text"])
      end

      box = recall["leitner_start_box"]
      unless Schema::LEITNER_BOXES.include?(box)
        add("#{path}.recall.leitner_start_box", "must be between 1 and 5")
      end

      threshold = recall["mastery_threshold"]
      if threshold != Schema::MASTERY_SCORE
        add("#{path}.recall.mastery_threshold", "must be #{Schema::MASTERY_SCORE} to match the mastery rule")
      end

      language_focus = item["language_focus"]
      if !language_focus.is_a?(Array) || language_focus.empty?
        add("#{path}.language_focus", "must name at least one language axis")
      elsif (language_focus - Schema::LANGUAGE_AXES).any?
        add("#{path}.language_focus", "unknown axes: #{(language_focus - Schema::LANGUAGE_AXES).join(", ")}")
      end
    end

    def validate_sources(item, path)
      sources = item["sources"]
      unless sources.is_a?(Array) && sources.any?
        return add("#{path}.sources", "must attribute at least one source")
      end

      sources.each_with_index { |source, index| validate_source("#{path}.sources[#{index}]", source) }
    end

    def validate_source(path, source)
      unless source.is_a?(Hash)
        return add(path, "must be a Hash")
      end

      Schema::REQUIRED_SOURCE_KEYS.each do |key|
        add("#{path}.#{key}", "is required") if blank?(source[key])
      end

      repo = source["repo"]
      unless Schema::SOURCE_REPOS.include?(repo)
        add("#{path}.repo", "#{repo.inspect} is not a known source repo")
      end

      check_length("#{path}.note", source["note"], Schema::MIN_LENGTHS["source_note"])

      path_value = source["path"]
      if repo == "system-design-estudos" && path_value.is_a?(String) && !path_value.end_with?(".md")
        add("#{path}.path", "corpus references must point at a Markdown file")
      end
    end

    def validate_template_binding(item, path)
      template = item["template"]

      if Schema.template_required?(target_key) && blank?(template)
        return add("#{path}.template", "target #{target_key} requires a template id on every item")
      end

      return if blank?(template)

      unless template_ids.include?(template)
        add("#{path}.template", "#{template.inspect} is not defined in pack templates")
      end
    end

    # The rendered controls must never contain the answer. The cheapest robust
    # check is that prompt and context do not quote a long span of it.
    def validate_no_answer_leak(item, path)
      best = item["best_answer"]
      return unless best.is_a?(String)

      spans = significant_spans(best)
      return if spans.empty?

      %w[prompt context].each do |field|
        value = item[field]
        next unless value.is_a?(String)

        haystack = normalize(value)
        leaked = spans.find { |span| haystack.include?(span) }
        add("#{path}.#{field}", "leaks the best answer span #{leaked.inspect}") if leaked
      end
    end

    SPAN_WORDS = 7

    def significant_spans(text)
      words = normalize(text).split(" ")
      return [] if words.size < SPAN_WORDS

      words.each_cons(SPAN_WORDS).map { |chunk| chunk.join(" ") }
    end

    def normalize(text)
      text.downcase.gsub(/[^a-z0-9 ]/, " ").squeeze(" ").strip
    end

    def check_length(path, value, minimum)
      return unless value.is_a?(String)
      return if value.strip.length >= minimum

      add(path, "is too short (#{value.strip.length} chars, need >= #{minimum})")
    end

    def blank?(value)
      value.nil? || (value.respond_to?(:empty?) && value.empty?) || (value.is_a?(String) && value.strip.empty?)
    end
  end
end
