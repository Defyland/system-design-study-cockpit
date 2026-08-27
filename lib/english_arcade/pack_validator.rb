# frozen_string_literal: true

require_relative "schema"
require "date"

module EnglishArcade
  # Validates a single target pack against EnglishArcade::Schema.
  #
  # The validator is deliberately strict and deliberately boring: every rule
  # maps to a failure a learner would actually notice, such as a leaked answer,
  # a distractor nobody would ever pick, or feedback that says nothing.
  class PackValidator
    IMPLEMENTATION_EVIDENCE_BASENAME = /\A(?:secrets?|credentials?|local_secret|token|private[_-]?key)\.(?:c|cc|clj|cljs|cpp|cs|ex|exs|fs|fsx|go|h|hpp|java|js|jsx|kt|kts|php|py|rb|rs|scala|swift|ts|tsx)\z/i
    SENSITIVE_EVIDENCE_PATH = %r{(?:^|/)(?:\.env(?:\.[^/]+)?|secrets?(?:\.[^/]+)?|credentials?(?:\.[^/]+)?|master\.key|local_secret(?:\.[^/]+)?|id_rsa(?:\.[^/]+)?|token(?:\.[^/]+)?|private[_-]?key(?:\.[^/]+)?)(?:/|$)}i
    KAMAL_SECRETS_PATH = %r{(?:^|/)\.kamal/secrets?(?:\.[^/]+)?(?:/|$)}i

    Error = Struct.new(:path, :message, keyword_init: true) do
      def to_s = "#{path}: #{message}"
    end

    attr_reader :errors, :warnings

    # strict: also treat publishable-bar shortfalls (fewer than 12 items) as
    # errors. Release runs strict; authoring runs lenient and reads warnings.
    def initialize(pack, strict: true, reference_date: nil)
      @pack = pack
      @strict = strict
      @errors = []
      @warnings = []
      @reference_date = normalize_reference_date(reference_date || default_reference_date)
    end

    def self.validate!(pack, strict: true, reference_date: nil)
      validator = new(pack, strict: strict, reference_date: reference_date)
      return true if validator.valid?

      raise ArgumentError, "Invalid English Arcade pack:\n#{validator.errors.join("\n")}"
    end

    # Provenance may cite implementation files such as `secrets.go`, but never
    # secret material itself or a file nested under a sensitive directory.
    def self.sensitive_evidence_path?(value)
      return false unless value.is_a?(String)
      return true if value.match?(KAMAL_SECRETS_PATH)

      segments = value.split("/")
      segments[-1] = "implementation_source" if segments.last&.match?(IMPLEMENTATION_EVIDENCE_BASENAME)
      segments.join("/").match?(SENSITIVE_EVIDENCE_PATH)
    end

    # Cross-pack content guard used by the standalone release validator. It
    # catches copied coaching prompts without rejecting ordinary interviewer
    # words that recur naturally (short n-grams and high stop-word windows are
    # deliberately ignored).
    def self.cross_pack_prompt_errors(packs)
      errors = []
      records = packs.to_h.flat_map do |target, pack|
        next [] unless Schema::CANONICAL_INTERVIEW_CONTENT_TARGETS.include?(target.to_s)

        target_label = target.to_s
        unless pack.is_a?(Hash)
          errors << "target=#{target_label}; collection=items; reason=pack must be a Hash"
          next []
        end
        unless pack.key?("items")
          errors << "target=#{target_label}; collection=items; reason=missing items array"
          next []
        end

        items = pack["items"]
        unless items.is_a?(Array)
          reason = items.nil? ? "must be an array (nil)" : "must be an array"
          errors << "target=#{target_label}; collection=items; reason=#{reason}"
          next []
        end

        # Member-shape diagnostics belong to the pack validator. The oracle
        # skips malformed members after the collection guard so it never
        # crashes or invents a second prompt finding for the same item.
        items.filter_map do |item|
          next unless item.is_a?(Hash)

          Schema::CANONICAL_INTERVIEW_CONTENT_TARGETS.include?(target.to_s) ? {
            "target" => target.to_s,
            "id" => item["id"].to_s,
            "topic" => item["topic"].to_s,
            "follow_up" => item["follow_up"].is_a?(Hash) ? item["follow_up"]["prompt"] : nil,
            "compression" => item["compression"].is_a?(Hash) ? item["compression"]["prompt"] : nil,
            "failure_probe" => item.dig("critical_thinking", "failure_probe", "prompt"),
            "extension" => item["extension"].is_a?(Hash) ? item["extension"]["prompt"] : nil,
            "certainty_update" => item.dig("critical_thinking", "certainty", "update_trigger"),
            "delayed_variant" => item.dig("recall", "delayed_variant", "prompt")
          } : nil
        end
      end
      prompt_rules = {
        "follow_up" => { ngram_size: 10, minimum_distinct: 2 },
        "compression" => { ngram_size: 8, minimum_distinct: 3 },
        "failure_probe" => { ngram_size: 8, minimum_distinct: 3 },
        "extension" => { ngram_size: 8, minimum_distinct: 3 },
        "certainty_update" => { ngram_size: 8, minimum_distinct: 3 },
        "delayed_variant" => { ngram_size: 8, minimum_distinct: 3 }
      }
      prompt_rules.each do |field, rules|
        values = records.filter_map do |record|
          prompt = record[field]
          next unless prompt.is_a?(String) && !prompt.strip.empty?

          [ normalize_prompt(prompt), record ]
        end
        values.group_by(&:first).each do |normalized, entries|
          next unless entries.map { |entry| entry.last["id"] }.uniq.length > 1

          errors << "#{field} prompt duplicated across #{entries.map { |entry| entry.last["id"] }.uniq.join(', ')}: #{normalized.inspect}"
        end

        ngram_size = rules.fetch(:ngram_size)
        ngrams = Hash.new { |hash, key| hash[key] = [] }
        values.each do |normalized, record|
          words = normalized.split(" ")
          anchor_words = normalize_prompt(record["topic"]).split(" ").reject { |word| word.length < 4 }
          words.each_cons(ngram_size) do |ngram|
            next if ngram.uniq.length < 5
            next if ngram.count { |word| GENERIC_PROMPT_WORDS.include?(word) } >= (ngram_size * 0.6)
            next if anchor_words.any? && (anchor_words & ngram).empty?

            ngrams[ngram.join(" ")] << record
          end
        end
        ngrams.each do |ngram, matching_records|
          distinct = matching_records.uniq { |record| record["id"] }
          next unless distinct.length >= rules.fetch(:minimum_distinct)

          errors << "#{field} prompt repeats a #{ngram_size}-gram across #{distinct.map { |record| record["id"] }.join(', ')}: #{ngram.inspect}"
        end
      end
      errors
    end

    def self.normalize_prompt(value)
      value.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squeeze(" ").strip
    end

    GENERIC_PROMPT_WORDS = %w[
      a an and are be can could do does for how if in is it me name now of on
      one or the their then this to what would you your
    ].freeze

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

    def default_reference_date
      Date.respond_to?(:current) ? Date.current : Date.today
    end

    def normalize_reference_date(value)
      return value if value.is_a?(Date)

      Date.iso8601(value.to_s)
    rescue ArgumentError, TypeError
      add("reference_date", "must be an ISO date")
      default_reference_date
    end

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

      unless Schema::SUPPORTED_CONTRACT_VERSIONS.include?(@pack["contract_version"])
        add("pack.contract_version", "must be one of #{Schema::SUPPORTED_CONTRACT_VERSIONS.join(', ')}")
      end
      add("pack.target", "missing target definition") unless @pack["target"].is_a?(Hash)
      malformed_collection_shape_error("items", "must be an array (missing items array)", path: "pack.items") unless @pack["items"].is_a?(Array)
    end

    def target_key
      target = @pack.is_a?(Hash) ? @pack["target"] : nil
      target.is_a?(Hash) ? target["key"] : nil
    end

    def validate_target
      target = @pack["target"]

      Schema::REQUIRED_TARGET_KEYS.each do |key|
        add("target.#{key}", "is required") if blank?(target[key])
      end

      unless Schema.target?(target["key"])
        add("target.key", "#{target["key"].inspect} is not a known target")
      end

      if canonical_content? && !Schema::CANONICAL_CONTRACT_VERSIONS.include?(@pack["contract_version"])
        add("pack.contract_version", "canonical target #{target_key} must use one of #{Schema::CANONICAL_CONTRACT_VERSIONS.join(', ')}")
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

      validate_target_critical_thinking if canonical_content?
    end

    def canonical_content?
      Schema::CANONICAL_INTERVIEW_CONTENT_TARGETS.include?(target_key)
    end

    def v14_content?
      canonical_content? && @pack["contract_version"] == Schema::CONTRACT_VERSION
    end

    def v15_content?
      canonical_content? && @pack["contract_version"] == Schema::TRANSITION_CONTRACT_VERSION
    end

    def validate_target_critical_thinking
      critical = @pack.dig("target", "critical_thinking")
      unless critical.is_a?(Hash)
        return add("target.critical_thinking", "must be a Hash for canonical interview content")
      end

      missing = Schema::REQUIRED_TARGET_CRITICAL_THINKING_KEYS - critical.keys
      extra = critical.keys - Schema::REQUIRED_TARGET_CRITICAL_THINKING_KEYS
      add("target.critical_thinking", "missing keys: #{missing.join(', ')}") if missing.any?
      add("target.critical_thinking", "unknown keys: #{extra.join(', ')}") if extra.any?

      prompts = critical["learner_prompts"]
      unless prompts.is_a?(Hash)
        add("target.critical_thinking.learner_prompts", "must be a Hash")
      else
        missing_prompts = Schema::REQUIRED_TARGET_CRITICAL_THINKING_PROMPTS - prompts.keys
        extra_prompts = prompts.keys - Schema::REQUIRED_TARGET_CRITICAL_THINKING_PROMPTS
        add("target.critical_thinking.learner_prompts", "missing keys: #{missing_prompts.join(', ')}") if missing_prompts.any?
        add("target.critical_thinking.learner_prompts", "unknown keys: #{extra_prompts.join(', ')}") if extra_prompts.any?
        Schema::REQUIRED_TARGET_CRITICAL_THINKING_PROMPTS.each do |key|
          check_text("target.critical_thinking.learner_prompts.#{key}", prompts[key], 40)
        end
      end

      rubric = critical["rubric"]
      unless rubric.is_a?(Hash)
        add("target.critical_thinking.rubric", "must be a Hash")
      else
        missing_axes = Schema::CRITICAL_THINKING_RUBRIC_AXES - rubric.keys
        extra_axes = rubric.keys - Schema::CRITICAL_THINKING_RUBRIC_AXES
        add("target.critical_thinking.rubric", "missing axes: #{missing_axes.join(', ')}") if missing_axes.any?
        add("target.critical_thinking.rubric", "unknown axes: #{extra_axes.join(', ')}") if extra_axes.any?
        Schema::CRITICAL_THINKING_RUBRIC_AXES.each do |axis|
          check_text("target.critical_thinking.rubric.#{axis}", rubric[axis], 30)
        end
      end
    end

    def validate_templates
      templates = @pack.key?("templates") ? @pack["templates"] : []

      unless templates.is_a?(Array)
        malformed_collection_shape_error("templates", "must be an array")
        return
      end

      if Schema.template_required?(target_key) && templates.empty?
        add("templates", "target #{target_key} requires at least one answer template")
      end

      templates.each_with_index do |template, index|
        path = "templates[#{index}]"
        unless template.is_a?(Hash)
          malformed_collection_member_error("templates", index)
          next
        end

        Schema::REQUIRED_TEMPLATE_KEYS.each do |key|
          add("#{path}.#{key}", "is required") if blank?(template[key])
        end

        steps = template["steps"]
        add("#{path}.steps", "must list at least 3 ordered steps") if !steps.is_a?(Array) || steps.size < 3
        validate_source("#{path}.source", template["source"]) if template["source"]
      end
    end

    def template_ids
      templates = @pack["templates"]
      return [] unless templates.is_a?(Array)

      templates.filter_map { |template| template["id"] if template.is_a?(Hash) }
    end

    def validate_items
      items = @pack["items"]
      return unless items.is_a?(Array)

      if items.size < Schema::MINIMUM_ITEMS_PER_TARGET
        add("items", "target #{target_key} has #{items.size} items, needs >= #{Schema::MINIMUM_ITEMS_PER_TARGET}")
      elsif items.size < Schema::PUBLISHABLE_ITEMS_PER_TARGET
        add_or_warn("items", "target #{target_key} has #{items.size} items, publishable bar is #{Schema::PUBLISHABLE_ITEMS_PER_TARGET}")
      end

      ids = items.filter_map { |item| item["id"] if item.is_a?(Hash) }
      duplicates = ids.tally.select { |_, count| count > 1 }.keys
      add("items", "duplicate item ids: #{duplicates.join(", ")}") if duplicates.any?

      items.each_with_index { |item, index| validate_item(item, "items[#{index}]") }
      validate_interview_prompt_uniqueness(items)
      validate_critical_thinking_distributions(items) if canonical_content?
      validate_defense_check_ids(items) if canonical_content?
    end

    def validate_critical_thinking_distributions(items)
      challenge_counts = items.filter_map do |item|
        item.is_a?(Hash) && item["follow_up"].is_a?(Hash) ? item["follow_up"]["challenge_kind"] : nil
      end.tally
      Schema::CRITICAL_THINKING_CHALLENGE_KINDS.each do |kind|
        count = challenge_counts.fetch(kind, 0)
        add("items.follow_up.challenge_kind", "#{kind} appears #{count} times; each challenge kind needs >= 2 per pack") if count < 2
      end

      failure_counts = items.filter_map do |item|
        item.is_a?(Hash) && item["critical_thinking"].is_a?(Hash) && item["critical_thinking"]["failure_probe"].is_a?(Hash) ? item["critical_thinking"]["failure_probe"]["kind"] : nil
      end.tally
      Schema::CRITICAL_THINKING_FAILURE_KINDS.each do |kind|
        count = failure_counts.fetch(kind, 0)
        add("items.critical_thinking.failure_probe.kind", "#{kind} appears #{count} times; each failure kind needs >= 2 per pack") if count < 2
      end

      false_comparisons = items.count do |item|
        item.is_a?(Hash) && item["critical_thinking"].is_a?(Hash) && item["critical_thinking"]["comparison"].is_a?(Hash) && item["critical_thinking"]["comparison"]["applicable"] == false
      end
      add("items.critical_thinking.comparison", "pack needs at least one honest non-comparison case") if false_comparisons.zero?
    end

    def validate_defense_check_ids(items)
      ids = items.filter_map do |item|
        next unless item.is_a?(Hash)

        checks = item.dig("critical_thinking", "defense_checks")
        next unless checks.is_a?(Array)

        checks.filter_map { |check| check.is_a?(Hash) ? check["id"] : nil }
      end.flatten
      duplicates = ids.tally.select { |_id, count| count > 1 }.keys
      add("items.critical_thinking.defense_checks", "duplicate defense check ids: #{duplicates.join(', ')}") if duplicates.any?
    end

    def validate_interview_prompt_uniqueness(items)
      return unless Schema::CANONICAL_INTERVIEW_CONTENT_TARGETS.include?(target_key)

      %w[follow_up compression].each do |field|
        prompts = items.each_with_index.filter_map do |item, index|
          value = item.is_a?(Hash) ? item[field] : nil
          prompt = value.is_a?(Hash) ? value["prompt"] : nil
          next unless prompt.is_a?(String) && !prompt.strip.empty?

          [ normalize(prompt), index ]
        end
        duplicates = prompts.group_by(&:first).select { |_prompt, entries| entries.length > 1 }
        duplicates.each do |prompt, entries|
          add("items", "repeated #{field} prompt across items #{entries.map(&:last).join(', ')}: #{prompt.inspect}")
        end
      end
    end

    def validate_item(item, path)
      return malformed_collection_member_error("items", item_index(path)) unless item.is_a?(Hash)

      Schema::REQUIRED_ITEM_KEYS.each do |key|
        add("#{path}.#{key}", "is required") if blank?(item[key])
      end

      optional_keys = Schema::OPTIONAL_ITEM_KEYS
      unless Schema::RESPONSE_VERSIONS_ALLOWED_CONTRACT_VERSIONS.include?(@pack["contract_version"])
        optional_keys = optional_keys - [ "response_versions" ]
      end
      unknown = item.keys - Schema::REQUIRED_ITEM_KEYS - optional_keys
      if unknown.any?
        message = "unknown keys: #{unknown.join(", ")}"
        if unknown.include?("response_versions")
          response_versions_error(item, path, message, field: "response_versions")
        else
          add("#{path}", message)
        end
      end

      validate_item_identity(item, path)
      validate_item_prose(item, path)
      validate_response_versions(item, path) if item.key?("response_versions") || v16_content?
      validate_distractors(item, path)
      validate_feedback(item, path)
      validate_rephrase(item, path)
      validate_interview_prompts(item, path)
      validate_feynman(item, path)
      validate_black_box(item, path)
      validate_recall(item, path)
      validate_sources(item, path)
      validate_provenance(item, path)
      validate_template_binding(item, path)
      validate_critical_thinking(item, path) if canonical_content?
      validate_extension(item, path) if canonical_content?
      validate_no_answer_leak(item, path)
      validate_repeated_determiners(item, path)
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
      expected_version = if v14_content?
        Schema::CONTRACT_VERSION
      elsif transition_content?
        if v16_content?
          Schema::RESPONSE_VERSIONS_CONTRACT_VERSION
        else
          Schema::TRANSITION_CONTRACT_VERSION
        end
      end
      if expected_version && version != expected_version
        item_context_error(
          item,
          "#{path}.version",
          "canonical #{@pack["contract_version"]} content must use #{expected_version}",
          field: "version"
        )
      end

      unless Schema::DIFFICULTIES.include?(item["difficulty"])
        add("#{path}.difficulty", "must be one of #{Schema::DIFFICULTIES.to_a.join(", ")}")
      end

      unless Schema::INTERVIEW_STAGES.include?(item["interview_stage"])
        add("#{path}.interview_stage", "#{item["interview_stage"].inspect} is not a known stage")
      end
    end

    def validate_response_versions(item, path)
      response_versions = item["response_versions"]
      unless response_versions.is_a?(Hash)
        return response_versions_error(item, "#{path}.response_versions", "must be a Hash with short, medium, and deep strings")
      end

      response_path = "#{path}.response_versions"
      missing = Schema::REQUIRED_RESPONSE_VERSION_KEYS - response_versions.keys
      extra = response_versions.keys - Schema::REQUIRED_RESPONSE_VERSION_KEYS
      response_versions_error(item, response_path, "missing keys: #{missing.join(', ')}") if missing.any?
      response_versions_error(item, response_path, "unknown keys: #{extra.join(', ')}") if extra.any?
      word_counts = {}
      Schema::REQUIRED_RESPONSE_VERSION_KEYS.each do |key|
        value = response_versions[key]
        value_path = "#{response_path}.#{key}"
        unless value.is_a?(String) && !value.strip.empty?
          response_versions_error(item, value_path, "must be a non-empty String")
          next
        end

        if value.match?(/\A\p{Space}*(?:short|medium|deep)\p{Space}*:/i)
          response_versions_error(item, value_path, "must not contain a Short:, Medium:, or Deep: heading")
        end

        word_count = normalized_tokens(value).length
        word_counts[key] = word_count
        range = Schema::RESPONSE_VERSION_WORD_RANGES.fetch(key)
        unless range.cover?(word_count)
          response_versions_error(item, value_path, "must contain #{range.begin}-#{range.end} words (got #{word_count})")
        end
      end

      if word_counts.values_at(*Schema::REQUIRED_RESPONSE_VERSION_KEYS).all?
        short_words, medium_words, deep_words = Schema::REQUIRED_RESPONSE_VERSION_KEYS.map { |key| word_counts.fetch(key) }
        response_versions_error(item, response_path, "word counts must increase strictly short < medium < deep (got #{short_words} < #{medium_words} < #{deep_words})") unless short_words < medium_words && medium_words < deep_words
      end

      medium = response_versions["medium"]
      best_answer = item["best_answer"]
      if medium.is_a?(String) && best_answer.is_a?(String) && normalize_whitespace(medium) != normalize_whitespace(best_answer)
        response_versions_error(item, "#{response_path}.medium", "must match best_answer after conservative whitespace normalization")
      end
    end

    # 1.5 fields remain required for the 1.6 promotion; response versions are
    # deliberately content-side and do not attempt to prove semantic identity.
    # Same thesis/facts/certainty remain an editorial or human-QA boundary.
    def transition_content?
      v15_content? || v16_content?
    end

    def v16_content?
      canonical_content? && @pack["contract_version"] == Schema::RESPONSE_VERSIONS_CONTRACT_VERSION
    end

    def normalize_whitespace(value)
      value.to_s.gsub(/\p{Space}+/, " ").strip
    end

    def normalized_tokens(value)
      normalize_whitespace(value).split(" ")
    end

    def response_versions_error(item, path, message, field: nil)
      item_context_error(item, path, message, field: field || context_field(path))
    end

    def item_context_error(item, path, message, field:)
      context = [
        "target=#{pack_target_label}",
        "item_index=#{item_index(path)}",
        item_id_label(item),
        "field=#{field}",
        "reason=#{message}"
      ].join("; ")
      add(path, "#{message} (#{context})")
    end

    def item_id_label(item)
      item_id = item.is_a?(Hash) ? item["id"].to_s : ""
      "item_id=#{item_id.empty? ? 'unknown' : item_id}"
    end

    def pack_target_label
      target = @pack.is_a?(Hash) && @pack["target"].is_a?(Hash) ? @pack["target"]["key"] : nil
      target = target.to_s.strip
      target.empty? ? "unknown" : target
    end

    def item_index(path)
      path.to_s[/\Aitems\[(\d+)\]/, 1] || "unknown"
    end

    def malformed_collection_member_error(collection, index)
      path = "#{collection}[#{index}]"
      add(path, "target=#{pack_target_label}; collection=#{collection}; index=#{index}; reason=must be a Hash")
    end

    def malformed_collection_shape_error(collection, reason, path: collection)
      add(path, "target=#{pack_target_label}; collection=#{collection}; reason=#{reason}")
    end

    def context_field(path)
      field = path.to_s.sub(/\Aitems\[\d+\]\./, "")
      field.empty? ? "unknown" : field
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

      validate_distractor_word_length_tell(best, distractors, "#{path}.distractors") if v16_content?
    end

    # If any distractor is far shorter than the best answer, a learner can score
    # without reading. Check each choice independently: using only the longest
    # distractor lets another short choice remain an obvious tell.
    def validate_distractor_word_length_tell(best, distractors, distractors_path)
      return unless best.is_a?(String) && distractors.is_a?(Array)

      best_words = normalized_tokens(best).length
      minimum_words = [
        (best_words.fdiv(Schema::BEST_ANSWER_TO_DISTRACTOR_WORD_RATIO)).ceil,
        Schema::MAX_DISTRACTOR_WORDS_FOR_LENGTH_TELL
      ].min

      distractors.each_with_index do |distractor, index|
        next unless distractor.is_a?(Hash) && distractor["text"].is_a?(String)

        distractor_words = normalized_tokens(distractor["text"]).length
        next unless distractor_words < minimum_words

        add(
          "#{distractors_path}[#{index}].text",
          "length alone reveals an obvious short option: has #{distractor_words} words vs " \
            "best answer #{best_words}; minimum #{minimum_words} words " \
            "(ratio #{Schema::BEST_ANSWER_TO_DISTRACTOR_WORD_RATIO}, " \
            "cap #{Schema::MAX_DISTRACTOR_WORDS_FOR_LENGTH_TELL})"
        )
      end
    end

    def validate_adaptive_length_tell(best, distractors_path, distractors)
      return unless adaptive_distractors_structurally_valid?(best, distractors)

      validate_distractor_word_length_tell(best, distractors, distractors_path)
    end

    def adaptive_distractors_structurally_valid?(best, distractors)
      return false unless adaptive_best_answer_structurally_valid?(best)
      return false unless distractors.is_a?(Array) && distractors.length == 2

      distractors.all? { |distractor| adaptive_distractor_structurally_valid?(distractor) }
    end

    def adaptive_best_answer_structurally_valid?(best)
      best.is_a?(String) && best.strip.length >= Schema::MIN_LENGTHS.fetch("best_answer")
    end

    def adaptive_distractor_structurally_valid?(distractor)
      return false unless distractor.is_a?(Hash)
      return false unless (Schema::REQUIRED_ADAPTIVE_DISTRACTOR_KEYS - distractor.keys).empty?
      return false unless (distractor.keys - Schema::REQUIRED_ADAPTIVE_DISTRACTOR_KEYS).empty?

      adaptive_distractor_field_structurally_valid?(distractor, "text", "distractor_text") &&
        adaptive_distractor_field_structurally_valid?(distractor, "why_wrong", "why_wrong")
    end

    def adaptive_distractor_field_structurally_valid?(distractor, key, minimum_key)
      value = distractor[key]
      value.is_a?(String) && !value.strip.empty? && value.strip.length >= Schema::MIN_LENGTHS.fetch(minimum_key)
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

    COMPRESSION_OPENERS = %w[
      compress summarize rephrase restate reduce preserve rewrite give state
      turn explain close frame compare outline name retell describe diagnose
      choose clarify make map tell contrast defend walk phrase reply set answer
      summarise open define sketch identify design specify list trace discuss use connect draft propose write
    ].freeze
    COMPRESSION_FRAMING = /\A(?:in\b[^:,.!?]{0,100}[,:]\s*|a\b[^:,.!?]{0,100}:\s*|briefly\s+)(?:#{COMPRESSION_OPENERS.join('|')})\b/i

    def validate_interview_prompts(item, path)
      return unless Schema::CANONICAL_INTERVIEW_CONTENT_TARGETS.include?(target_key)

      authored_prompts = {}
      follow_up = item["follow_up"]
      unless follow_up.is_a?(Hash)
        add("#{path}.follow_up", "must be a Hash with an authored prompt for canonical interview content")
      else
        validate_exact_keys(
          follow_up,
          transition_content? ? Schema::REQUIRED_TRANSITION_FOLLOW_UP_KEYS : Schema::REQUIRED_FOLLOW_UP_KEYS,
          "#{path}.follow_up",
          optional: transition_content? ? [] : Schema::OPTIONAL_FOLLOW_UP_KEYS
        )
        prompt = follow_up["prompt"]
        add("#{path}.follow_up.prompt", "is required") if blank?(prompt)
        check_length("#{path}.follow_up.prompt", prompt, Schema::MIN_LENGTHS.fetch("follow_up_prompt"))
        authored_prompts["follow_up"] = normalize(prompt) if prompt.is_a?(String) && prompt.strip.length >= Schema::MIN_LENGTHS.fetch("follow_up_prompt")
        add("#{path}.follow_up.prompt", "must be a real interviewer question") if prompt.is_a?(String) && !prompt.include?("?")
        check_text("#{path}.follow_up.goal", follow_up["goal"], 25)
        unless Schema::CRITICAL_THINKING_CHALLENGE_KINDS.include?(follow_up["challenge_kind"])
          add("#{path}.follow_up.challenge_kind", "must be one of #{Schema::CRITICAL_THINKING_CHALLENGE_KINDS.join(', ')}")
        end
        check_text("#{path}.follow_up.best_answer", follow_up["best_answer"], Schema::MIN_LENGTHS["best_answer"])
        validate_adaptive_distractors(
          follow_up["distractors"],
          "#{path}.follow_up.distractors",
          best_answer: follow_up["best_answer"]
        )
        validate_adaptive_length_tell(
          follow_up["best_answer"],
          "#{path}.follow_up.distractors",
          follow_up["distractors"]
        ) if v16_content?
        if follow_up["best_answer"].is_a?(String) && normalize(follow_up["best_answer"]) == normalize(item["best_answer"])
          add("#{path}.follow_up.best_answer", "must answer the challenge rather than repeat the base answer")
        end
        validate_answer_anchors(follow_up["answer_anchors"], "#{path}.follow_up.answer_anchors") if transition_content? || follow_up.key?("answer_anchors")
      end

      compression = item["compression"]
      unless compression.is_a?(Hash)
        add("#{path}.compression", "must be a Hash with an authored prompt for canonical interview content")
      else
        validate_exact_keys(compression, %w[prompt goal], "#{path}.compression")
        prompt = compression["prompt"]
        add("#{path}.compression.prompt", "is required") if blank?(prompt)
        check_length("#{path}.compression.prompt", prompt, Schema::MIN_LENGTHS.fetch("compression_prompt"))
        authored_prompts["compression"] = normalize(prompt) if prompt.is_a?(String) && prompt.strip.length >= Schema::MIN_LENGTHS.fetch("compression_prompt")
        if prompt.is_a?(String) && !prompt.include?("?") && !compression_prompt_actionable?(prompt)
          add("#{path}.compression.prompt", "must be an actionable spoken imperative or question")
        end
        check_text("#{path}.compression.goal", compression["goal"], 25)
      end
      if authored_prompts["follow_up"] && authored_prompts["follow_up"] == authored_prompts["compression"]
        add("#{path}.compression.prompt", "must not duplicate the follow-up prompt")
      end
      validate_adaptive_depths(item, path)
    end

    def validate_adaptive_depths(item, path)
      prompts = {
        "initial" => item["prompt"],
        "rephrase" => item["rephrase"].is_a?(Hash) ? item["rephrase"]["prompt"] : nil,
        "follow_up" => item["follow_up"].is_a?(Hash) ? item["follow_up"]["prompt"] : nil,
        "compression" => item["compression"].is_a?(Hash) ? item["compression"]["prompt"] : nil,
        "extension" => item["extension"].is_a?(Hash) ? item["extension"]["prompt"] : nil,
        "delayed_variant" => item["recall"].is_a?(Hash) && item["recall"]["delayed_variant"].is_a?(Hash) ? item["recall"]["delayed_variant"]["prompt"] : nil
      }.compact
      normalized = prompts.transform_values { |prompt| normalize(prompt) }
      normalized.group_by { |_name, value| value }.each do |value, entries|
        next if entries.length < 2

        add("#{path}.adaptive", "rephrase, compression, extension, follow-up, and delayed prompts must be distinct: #{value.inspect}")
      end

      delayed = item["recall"].is_a?(Hash) ? item["recall"]["delayed_variant"] : nil
      return unless delayed.is_a?(Hash)

      add("#{path}.recall.delayed_variant.id", "must be a stable item-derived id") unless delayed["id"].is_a?(String) && delayed["id"].start_with?("#{item["id"]}-delayed-")
      if normalize(delayed["best_answer"]) == normalize(item["best_answer"])
        add("#{path}.recall.delayed_variant.best_answer", "must answer the delayed variant rather than repeat the base answer")
      end
    end

    def validate_adaptive_distractors(distractors, path, best_answer: nil)
      unless distractors.is_a?(Array)
        return add(path, "must be an array of two challenge distractors")
      end
      add(path, "must contain exactly two challenge distractors") unless distractors.length == 2
      normalized_texts = []
      distractors.each_with_index do |distractor, index|
        dpath = "#{path}[#{index}]"
        unless distractor.is_a?(Hash)
          add(dpath, "must be a Hash")
          next
        end
        validate_exact_keys(distractor, Schema::REQUIRED_ADAPTIVE_DISTRACTOR_KEYS, dpath)
        check_text("#{dpath}.text", distractor["text"], Schema::MIN_LENGTHS["distractor_text"])
        check_text("#{dpath}.why_wrong", distractor["why_wrong"], Schema::MIN_LENGTHS["why_wrong"])
        if distractor["text"].is_a?(String)
          normalized = normalize(distractor["text"])
          add("#{dpath}.text", "must be distinct from the other distractor") if normalized_texts.include?(normalized)
          normalized_texts << normalized unless normalized_texts.include?(normalized)
          if best_answer.is_a?(String) && normalized == normalize(best_answer)
            add("#{dpath}.text", "duplicates the best answer")
          end
        end
      end
    end

    def validate_answer_anchors(value, path)
      unless value.is_a?(Array)
        return add(path, "must be an array of 2-5 specific strings")
      end
      unless (2..5).cover?(value.length)
        add(path, "must contain between 2 and 5 specific strings")
      end

      normalized = []
      value.each_with_index do |anchor, index|
        apath = "#{path}[#{index}]"
        unless anchor.is_a?(String) && !anchor.strip.empty?
          add(apath, "must be a non-empty String")
          next
        end
        length = anchor.strip.length
        if length < Schema::ANSWER_ANCHOR_MIN_LENGTH
          add(apath, "is too short to be specific (#{length} chars, need >= #{Schema::ANSWER_ANCHOR_MIN_LENGTH})")
        elsif length > Schema::ANSWER_ANCHOR_MAX_LENGTH
          add(apath, "is too long to be a concise answer anchor (#{length} chars, need <= #{Schema::ANSWER_ANCHOR_MAX_LENGTH})")
        end
        key = normalize(anchor)
        add(apath, "must be distinct after normalization") if normalized.include?(key)
        normalized << key unless normalized.include?(key)
      end
    end

    def validate_extension(item, path)
      extension = item["extension"]
      unless extension.is_a?(Hash)
        return add("#{path}.extension", "must be a Hash with a deep prompt for canonical interview content")
      end
      validate_exact_keys(extension, Schema::REQUIRED_EXTENSION_KEYS, "#{path}.extension")
      prompt = extension["prompt"]
      check_text("#{path}.extension.prompt", prompt, Schema::MIN_LENGTHS["follow_up_prompt"])
      if prompt.is_a?(String) && !prompt.include?("?") && !compression_prompt_actionable?(prompt)
        add("#{path}.extension.prompt", "must be an actionable deep interviewer turn")
      end
      check_text("#{path}.extension.goal", extension["goal"], 25)
    end

    def validate_critical_thinking(item, path)
      critical = item["critical_thinking"]
      unless critical.is_a?(Hash)
        return add("#{path}.critical_thinking", "must be a Hash for canonical interview content")
      end
      validate_exact_keys(
        critical,
        transition_content? ? Schema::REQUIRED_TRANSITION_ITEM_CRITICAL_THINKING_KEYS : Schema::REQUIRED_ITEM_CRITICAL_THINKING_KEYS,
        "#{path}.critical_thinking",
        optional: transition_content? ? [] : Schema::OPTIONAL_ITEM_CRITICAL_THINKING_KEYS
      )
      check_text("#{path}.critical_thinking.problem_frame", critical["problem_frame"], 40)

      claim_map = critical["claim_map"]
      unless claim_map.is_a?(Hash)
        add("#{path}.critical_thinking.claim_map", "must be a Hash")
      else
        validate_exact_keys(claim_map, Schema::REQUIRED_CLAIM_MAP_KEYS, "#{path}.critical_thinking.claim_map")
        Schema::REQUIRED_CLAIM_MAP_KEYS.each do |key|
          check_text("#{path}.critical_thinking.claim_map.#{key}", claim_map[key], 25)
        end
      end

      validate_comparison(critical["comparison"], "#{path}.critical_thinking.comparison")
      validate_failure_probe(critical["failure_probe"], "#{path}.critical_thinking.failure_probe")
      validate_evidence_check(critical["evidence_check"], "#{path}.critical_thinking.evidence_check")
      validate_certainty(critical["certainty"], "#{path}.critical_thinking.certainty")
      validate_item_rubric(critical["rubric"], "#{path}.critical_thinking.rubric")
      validate_defense_checks(critical["defense_checks"], item["id"], "#{path}.critical_thinking.defense_checks") if transition_content? || critical.key?("defense_checks")
    end

    def validate_defense_checks(value, item_id, path)
      unless value.is_a?(Array)
        return add(path, "must be an array with exactly one defense check")
      end
      add(path, "must contain exactly one defense check") unless value.length == 1

      value.each_with_index do |check, index|
        cpath = "#{path}[#{index}]"
        unless check.is_a?(Hash)
          add(cpath, "must be a Hash")
          next
        end
        validate_exact_keys(check, Schema::DEFENSE_CHECK_KEYS, cpath)
        id = check["id"]
        unless id.is_a?(String) && !id.strip.empty? && id.start_with?("#{item_id}-defense-")
          add("#{cpath}.id", "must be a non-empty item-bound id starting with #{item_id}-defense-")
        end
        unless Schema::DEFENSE_CHECK_AXES.include?(check["axis"])
          add("#{cpath}.axis", "must be one of #{Schema::DEFENSE_CHECK_AXES.join(', ')}")
        end
        check_text("#{cpath}.prompt", check["prompt"], Schema::MIN_LENGTHS["follow_up_prompt"])
        add("#{cpath}.prompt", "must be a natural interviewer question") if check["prompt"].is_a?(String) && !check["prompt"].include?("?")
        check_text("#{cpath}.best_answer", check["best_answer"], Schema::MIN_LENGTHS["best_answer"])
        validate_adaptive_distractors(
          check["distractors"],
          "#{cpath}.distractors",
          best_answer: check["best_answer"]
        )
        validate_adaptive_length_tell(
          check["best_answer"],
          "#{cpath}.distractors",
          check["distractors"]
        ) if v16_content?
      end
    end

    def validate_comparison(comparison, path)
      unless comparison.is_a?(Hash)
        return add(path, "must be a Hash")
      end
      applicable = comparison["applicable"]
      unless applicable == true || applicable == false
        return add("#{path}.applicable", "must be boolean")
      end

      if applicable
        validate_exact_keys(comparison, Schema::REQUIRED_COMPARISON_TRUE_KEYS, path)
        alternatives = comparison["alternatives"]
        unless alternatives.is_a?(Array) && alternatives.length >= 2
          add("#{path}.alternatives", "must contain at least two distinct alternatives")
        else
          options = alternatives.map { |alternative| alternative.is_a?(Hash) ? alternative["option"].to_s : "" }
          add("#{path}.alternatives", "options must be distinct") if options.any?(&:empty?) || options.map { |option| normalize(option) }.uniq.length != options.length
          alternatives.each_with_index do |alternative, index|
            apath = "#{path}.alternatives[#{index}]"
            unless alternative.is_a?(Hash)
              add(apath, "must be a Hash")
              next
            end
            validate_exact_keys(alternative, Schema::REQUIRED_ALTERNATIVE_KEYS, apath)
            Schema::REQUIRED_ALTERNATIVE_KEYS.each { |key| check_text("#{apath}.#{key}", alternative[key], 20) }
          end
        end
      else
        validate_exact_keys(comparison, Schema::REQUIRED_COMPARISON_FALSE_KEYS, path)
        %w[rejected_alternative hard_constraint decision_rule].each do |key|
          check_text("#{path}.#{key}", comparison[key], 25)
        end
      end
      check_text("#{path}.decision_rule", comparison["decision_rule"], 30)
    end

    def validate_failure_probe(probe, path)
      unless probe.is_a?(Hash)
        return add(path, "must be a Hash")
      end
      validate_exact_keys(probe, Schema::REQUIRED_FAILURE_PROBE_KEYS, path)
      unless Schema::CRITICAL_THINKING_FAILURE_KINDS.include?(probe["kind"])
        add("#{path}.kind", "must be one of #{Schema::CRITICAL_THINKING_FAILURE_KINDS.join(', ')}")
      end
      check_text("#{path}.prompt", probe["prompt"], 40)
      add("#{path}.prompt", "must be a natural interviewer question") if probe["prompt"].is_a?(String) && !probe["prompt"].include?("?")
    end

    def validate_evidence_check(check, path)
      unless check.is_a?(Hash)
        return add(path, "must be a Hash")
      end
      validate_exact_keys(check, Schema::REQUIRED_EVIDENCE_CHECK_KEYS, path)
      check_text("#{path}.basis", check["basis"], 30)
      unless Schema::CRITICAL_THINKING_SOURCE_KINDS.include?(check["source_kind"])
        add("#{path}.source_kind", "must be one of #{Schema::CRITICAL_THINKING_SOURCE_KINDS.join(', ')}")
      end
      check_text("#{path}.limitation", check["limitation"], 30)
      checked_on = check["checked_on"]
      begin
        date = Date.iso8601(checked_on.to_s)
        add("#{path}.checked_on", "must not be in the future") if date > @reference_date
      rescue ArgumentError
        add("#{path}.checked_on", "must be an ISO date")
      end
    end

    def validate_certainty(certainty, path)
      unless certainty.is_a?(Hash)
        return add(path, "must be a Hash")
      end
      validate_exact_keys(certainty, Schema::REQUIRED_CERTAINTY_KEYS, path)
      unless Schema::CRITICAL_THINKING_CERTAINTY_LEVELS.include?(certainty["level"])
        add("#{path}.level", "must be one of #{Schema::CRITICAL_THINKING_CERTAINTY_LEVELS.join(', ')}")
      end
      check_text("#{path}.rationale", certainty["rationale"], 30)
      check_text("#{path}.update_trigger", certainty["update_trigger"], 30)
    end

    def validate_item_rubric(rubric, path)
      unless rubric.is_a?(Hash)
        return add(path, "must be a Hash")
      end
      validate_exact_keys(rubric, Schema::CRITICAL_THINKING_RUBRIC_AXES, path)
      Schema::CRITICAL_THINKING_RUBRIC_AXES.each do |axis|
        check_text("#{path}.#{axis}", rubric[axis], 30)
      end
    end

    def validate_exact_keys(hash, required, path, optional: [])
      missing = required - hash.keys
      extra = hash.keys - required - optional
      add(path, "missing keys: #{missing.join(', ')}") if missing.any?
      add(path, "unknown keys: #{extra.join(', ')}") if extra.any?
    end

    def compression_prompt_actionable?(prompt)
      first_word = prompt.strip.downcase.split(/[^a-z]+/).first
      COMPRESSION_OPENERS.include?(first_word) || prompt.match?(COMPRESSION_FRAMING)
    end

    # Feynman keys are exact: the session engine renders them positionally.
    def validate_feynman(item, path)
      feynman = item["feynman"]
      unless feynman.is_a?(Hash)
        return add("#{path}.feynman", "must be a Hash")
      end

      required_keys = canonical_content? ? Schema::REQUIRED_CANONICAL_FEYNMAN_KEYS : Schema::REQUIRED_FEYNMAN_KEYS
      missing = required_keys - feynman.keys
      add("#{path}.feynman", "missing keys: #{missing.join(", ")}") if missing.any?

      extra = feynman.keys - required_keys
      add("#{path}.feynman", "unknown keys: #{extra.join(", ")}") if extra.any?

      required_keys.each do |key|
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

      required_keys = canonical_content? ? Schema::REQUIRED_CANONICAL_BLACK_BOX_KEYS : Schema::REQUIRED_BLACK_BOX_KEYS
      missing = required_keys - black_box.keys
      add("#{path}.black_box", "missing keys: #{missing.join(", ")}") if missing.any?

      extra = black_box.keys - required_keys
      add("#{path}.black_box", "unknown keys: #{extra.join(", ")}") if extra.any?

      required_keys.each do |key|
        check_length("#{path}.black_box.#{key}", black_box[key], Schema::MIN_LENGTHS["black_box_text"])
      end
    end

    def validate_cards
      cards = @pack["cards"]
      unless cards.is_a?(Array)
        return malformed_collection_shape_error("cards", "must be an array of production Leitner cards")
      end

      if cards.size < Schema::MINIMUM_CARDS_PER_TARGET || cards.size > Schema::MAXIMUM_CARDS_PER_TARGET
        add("cards", "target #{target_key} has #{cards.size} cards, expected #{Schema::MINIMUM_CARDS_PER_TARGET}-#{Schema::MAXIMUM_CARDS_PER_TARGET}")
      end

      ids = cards.filter_map { |card| card["id"] if card.is_a?(Hash) }
      duplicates = ids.tally.select { |_, count| count > 1 }.keys
      add("cards", "duplicate card ids: #{duplicates.join(", ")}") if duplicates.any?

      cards.each_with_index do |card, index|
        cpath = "cards[#{index}]"
        unless card.is_a?(Hash)
          malformed_collection_member_error("cards", index)
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
        validate_card_critical_thinking(card, cpath) if canonical_content?
      end
    end

    def validate_card_critical_thinking(card, path)
      critical = card["critical_thinking"]
      unless critical.is_a?(Hash)
        return add("#{path}.critical_thinking", "must be a Hash for canonical cards")
      end

      missing = Schema::REQUIRED_CARD_CRITICAL_THINKING_KEYS - critical.keys
      extra = critical.keys - Schema::REQUIRED_CARD_CRITICAL_THINKING_KEYS
      add("#{path}.critical_thinking", "missing keys: #{missing.join(', ')}") if missing.any?
      add("#{path}.critical_thinking", "unknown keys: #{extra.join(', ')}") if extra.any?
      Schema::REQUIRED_CARD_CRITICAL_THINKING_KEYS.each do |key|
        check_text("#{path}.critical_thinking.#{key}", critical[key], 30)
      end
    end

    def validate_recall(item, path)
      recall = item["recall"]
      unless recall.is_a?(Hash)
        return add("#{path}.recall", "must be a Hash")
      end

      required_keys = canonical_content? ? Schema::REQUIRED_CANONICAL_RECALL_KEYS : Schema::REQUIRED_RECALL_KEYS
      required_keys.each do |key|
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

      validate_delayed_variant(recall["delayed_variant"], path) if canonical_content?

      language_focus = item["language_focus"]
      if !language_focus.is_a?(Array) || language_focus.empty?
        add("#{path}.language_focus", "must name at least one language axis")
      elsif (language_focus - Schema::LANGUAGE_AXES).any?
        add("#{path}.language_focus", "unknown axes: #{(language_focus - Schema::LANGUAGE_AXES).join(", ")}")
      end
    end

    def validate_delayed_variant(delayed, path)
      unless delayed.is_a?(Hash)
        return add("#{path}.recall.delayed_variant", "must be a Hash")
      end

      required_keys = transition_content? ? Schema::REQUIRED_TRANSITION_DELAYED_VARIANT_KEYS : Schema::REQUIRED_DELAYED_VARIANT_KEYS
      optional_keys = transition_content? ? [] : Schema::OPTIONAL_DELAYED_VARIANT_KEYS
      missing = required_keys - delayed.keys
      extra = delayed.keys - required_keys - optional_keys
      add("#{path}.recall.delayed_variant", "missing keys: #{missing.join(', ')}") if missing.any?
      add("#{path}.recall.delayed_variant", "unknown keys: #{extra.join(', ')}") if extra.any?

      check_text("#{path}.recall.delayed_variant.id", delayed["id"], 8)
      check_text("#{path}.recall.delayed_variant.prompt", delayed["prompt"], 40)
      check_text("#{path}.recall.delayed_variant.changed_constraint", delayed["changed_constraint"], 20)
      check_text("#{path}.recall.delayed_variant.new_evidence", delayed["new_evidence"], 20)
      check_text("#{path}.recall.delayed_variant.best_answer", delayed["best_answer"], Schema::MIN_LENGTHS["best_answer"])
      validate_adaptive_distractors(
        delayed["distractors"],
        "#{path}.recall.delayed_variant.distractors",
        best_answer: delayed["best_answer"]
      )
      validate_adaptive_length_tell(
        delayed["best_answer"],
        "#{path}.recall.delayed_variant.distractors",
        delayed["distractors"]
      ) if v16_content?
      validate_answer_anchors(delayed["answer_anchors"], "#{path}.recall.delayed_variant.answer_anchors") if transition_content? || delayed.key?("answer_anchors")
      validate_reasoning_moves(delayed["reasoning_moves"], "#{path}.recall.delayed_variant.reasoning_moves") if transition_content? || delayed.key?("reasoning_moves")
    end

    def validate_reasoning_moves(value, path)
      unless value.is_a?(Hash)
        return add(path, "must be a Hash with exactly the reasoning moves #{Schema::REASONING_MOVE_KEYS.join(', ')}")
      end
      validate_exact_keys(value, Schema::REASONING_MOVE_KEYS, path)
      Schema::REASONING_MOVE_KEYS.each do |key|
        check_text("#{path}.#{key}", value[key], Schema::REASONING_MOVE_MIN_LENGTH)
      end
    end

    def validate_sources(item, path)
      sources = item["sources"]
      unless sources.is_a?(Array) && sources.any?
        return add("#{path}.sources", "must attribute at least one source")
      end

      sources.each_with_index { |source, index| validate_source("#{path}.sources[#{index}]", source) }
    end

    # Provenance is intentionally separate from display sources. Sources teach
    # the learner where to read; provenance constrains what they may honestly
    # claim in an interview.
    def validate_provenance(item, path)
      provenance = item["provenance"]
      if Schema.provenance_required?(target_key) && !provenance.is_a?(Hash)
        return add("#{path}.provenance", "is required for #{target_key} items")
      end
      return if provenance.nil?
      return add("#{path}.provenance", "must be a Hash") unless provenance.is_a?(Hash)

      Schema::REQUIRED_PROVENANCE_KEYS.each do |key|
        add("#{path}.provenance.#{key}", "is required") if blank?(provenance[key])
      end

      evidence_class = provenance["evidence_class"]
      unless Schema::EVIDENCE_CLASSES.include?(evidence_class)
        add("#{path}.provenance.evidence_class", "#{evidence_class.inspect} is not a known evidence class")
      end
      %w[project repository safe_interview_version].each do |key|
        check_length("#{path}.provenance.#{key}", provenance[key], key == "safe_interview_version" ? 80 : 3)
      end

      files = provenance["files"]
      if !files.is_a?(Array) || files.empty?
        add("#{path}.provenance.files", "must list at least one evidence file")
      else
        files.each_with_index do |file, index|
          fpath = "#{path}.provenance.files[#{index}]"
          unless file.is_a?(Hash)
            add(fpath, "must be a Hash")
            next
          end
          Schema::REQUIRED_PROVENANCE_FILE_KEYS.each { |key| add("#{fpath}.#{key}", "is required") if blank?(file[key]) }
          validate_relative_evidence_path("#{fpath}.path", file["path"])
          add("#{fpath}.commit", "must be a 7-64 character lowercase hexadecimal SHA") unless file["commit"].is_a?(String) && file["commit"].match?(/\A[0-9a-f]{7,64}\z/)
          check_length("#{fpath}.claim", file["claim"], 20)
        end
      end

      claims = provenance["verified_claims"]
      if !claims.is_a?(Array) || claims.empty?
        add("#{path}.provenance.verified_claims", "must list at least one verified claim")
      else
        claims.each_with_index { |claim, index| check_length("#{path}.provenance.verified_claims[#{index}]", claim, 20) }
      end

      confirmations = provenance["confirmation_required"]
      unless confirmations.is_a?(Array)
        add("#{path}.provenance.confirmation_required", "must be an array")
      else
        confirmations.each_with_index { |point, index| check_length("#{path}.provenance.confirmation_required[#{index}]", point, 15) }
        if evidence_class == "resume_derived" && confirmations.empty?
          add("#{path}.provenance.confirmation_required", "must not be empty for resume-derived evidence")
        end
      end

      safe = provenance["safe_interview_version"]
      validate_safe_interview_version(safe, evidence_class, confirmations, path)
      validate_confidentiality(provenance["confidentiality"], path)
    end

    def validate_relative_evidence_path(path, value)
      return unless value.is_a?(String)

      if value.start_with?("/") || value.include?("..")
        add(path, "must be a relative path without '..'")
      end
      add(path, "must not name a sensitive file") if self.class.sensitive_evidence_path?(value)
    end

    def validate_safe_interview_version(value, evidence_class, confirmations, path)
      return unless value.is_a?(String)

      if %w[portfolio_code public_challenge].include?(evidence_class)
        add("#{path}.provenance.safe_interview_version", "must identify the work as a portfolio, study, or challenge") unless value.match?(/\b(portfolio|study|challenge)\b/i)
        forbidden = /\b(employer|production|customers?|on-call|business results?|production-scale performance)\b/i
        add("#{path}.provenance.safe_interview_version", "must not claim employer, production, customer, on-call, or business-result work") if value.match?(forbidden)
      end
      if evidence_class == "deployed_personal_project"
        add("#{path}.provenance.safe_interview_version", "must identify the work as a personal project or product") unless value.match?(/\b(personal project|personal product)\b/i)
        forbidden = /\b(employer|production|customers?|on-call|business results?|production-scale performance)\b/i
        add("#{path}.provenance.safe_interview_version", "must not claim employer, production, customer, on-call, or business-result work") if value.match?(forbidden)
      end
      return unless evidence_class == "resume_derived"

      combined = Array(confirmations).join(" ").downcase
      unless combined.match?(/r(?:é|e)sum(?:é|e) PDF is absent/i)
        add("#{path}.provenance.confirmation_required", "must disclose that the referenced résumé PDF is absent")
      end
      %w[ownership metrics mechanisms].each do |term|
        add("#{path}.provenance.confirmation_required", "must require confirmation of #{term} for resume-derived evidence") unless combined.include?(term)
      end
    end

    def validate_confidentiality(confidentiality, path)
      unless confidentiality.is_a?(Hash)
        return add("#{path}.provenance.confidentiality", "must be a Hash")
      end

      Schema::REQUIRED_CONFIDENTIALITY_KEYS.each { |key| add("#{path}.provenance.confidentiality.#{key}", "is required") if blank?(confidentiality[key]) }
      unless Schema::CONFIDENTIALITY_RISK_LEVELS.include?(confidentiality["level"])
        add("#{path}.provenance.confidentiality.level", "must be one of #{Schema::CONFIDENTIALITY_RISK_LEVELS.join(', ')}")
      end
      check_length("#{path}.provenance.confidentiality.note", confidentiality["note"], 15)
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

      validate_relative_evidence_path("#{path}.path", source["path"])

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

    # The rendered controls must never contain the answer. Prompt, context, and
    # every adaptation prompt are learner-visible before feedback; options are
    # intentionally excluded because one option is the answer by design.
    def validate_no_answer_leak(item, path)
      best = item["best_answer"]
      return unless best.is_a?(String)

      spans = significant_spans(best)
      return if spans.empty?

      %w[prompt context rephrase extension follow_up compression].each do |field|
        value = learner_visible_prompt(item[field])
        validate_answer_spans("#{path}.#{field}", value, spans)
      end

      feynman = item["feynman"]
      if feynman.is_a?(Hash)
        feynman_keys = canonical_content? ? Schema::REQUIRED_CANONICAL_FEYNMAN_KEYS : Schema::REQUIRED_FEYNMAN_KEYS
        feynman_keys.each do |key|
          validate_answer_spans("#{path}.feynman.#{key}", feynman[key], spans)
        end
      end
      delayed = item["recall"].is_a?(Hash) ? item["recall"]["delayed_variant"] : nil
      validate_answer_spans("#{path}.recall.delayed_variant.prompt", delayed["prompt"], spans) if delayed.is_a?(Hash)
      validate_critical_thinking_answer_leaks(item["critical_thinking"], "#{path}.critical_thinking", spans) if canonical_content?
    end

    # A generated article before a topic that already carries an article is a
    # small but visible naturalness failure (for example, "the a recruiter
    # introduction"). Fail closed so a future content batch cannot reintroduce
    # that interview-facing grammar defect.
    REPEATED_DETERMINERS = /\b(?:the|a|an)\s+(?:a|an|the)\s+/i

    def validate_repeated_determiners(value, path)
      case value
      when Hash
        value.each { |key, child| validate_repeated_determiners(child, "#{path}.#{key}") }
      when Array
        value.each_with_index { |child, index| validate_repeated_determiners(child, "#{path}[#{index}]") }
      when String
        add(path, "contains repeated determiners") if value.match?(REPEATED_DETERMINERS)
      end
    end

    def validate_critical_thinking_answer_leaks(value, path, spans)
      if value.is_a?(Array)
        value.each_with_index { |child, index| validate_critical_thinking_answer_leaks(child, "#{path}[#{index}]", spans) }
        return
      end
      return unless value.is_a?(Hash)

      value.each do |key, child|
        next if key.to_s == "best_answer"

        child_path = "#{path}.#{key}"
        if child.is_a?(String)
          validate_answer_spans(child_path, child, spans)
        elsif child.is_a?(Hash) || child.is_a?(Array)
          validate_critical_thinking_answer_leaks(child, child_path, spans)
        end
      end
    end

    def learner_visible_prompt(value)
      value.is_a?(Hash) ? value["prompt"] : value
    end

    def validate_answer_spans(path, value, spans)
      return unless value.is_a?(String)

      haystack = normalize(value)
      leaked = spans.find { |span| haystack.include?(span) }
      add(path, "leaks the best answer span #{leaked.inspect}") if leaked
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

    def check_text(path, value, minimum)
      unless value.is_a?(String) && !value.strip.empty?
        add(path, "must be a non-empty String")
        return
      end

      check_length(path, value, minimum)
    end

    def blank?(value)
      value.nil? || (value.respond_to?(:empty?) && value.empty?) || (value.is_a?(String) && value.strip.empty?)
    end
  end
end
