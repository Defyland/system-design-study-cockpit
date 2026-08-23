require "yaml"

module EnglishArcade
  class FixtureValidator
    TARGET_KEYS = %w[dsa ruby rails react golang elixir salesforce system_design].freeze
    REQUIRED_ITEM_KEYS = %w[id prompt context answer distractors feedback rephrase extension source_ref].freeze
    FEEDBACK_KEYS = %w[register hedging precision grammar pragmatics].freeze
    LEITNER_INTERVALS = { 1 => 1, 2 => 2, 3 => 4, 4 => 7, 5 => 14 }.freeze

    FIXTURE_PATH = File.expand_path("fixtures/english_c2_arcade.yml", __dir__)

    def self.load_fixture
      YAML.safe_load_file(FIXTURE_PATH, aliases: true)
    end

    def initialize(fixture)
      @fixture = fixture
      @errors = []
    end

    def valid?
      errors.empty?
    end

    def errors
      return @errors if @validated

      @validated = true
      validate_root
      validate_state_machine
      validate_targets
      validate_learning_loop
      validate_persistence
      validate_adaptation
      validate_accessibility
      validate_health
      @errors
    end

    private

    attr_reader :fixture

    def validate_root
      require_hash(fixture, "root")
      require_keys(fixture, %w[version product presentation state_machine targets learning_loop persistence adaptation accessibility health], "root")

      product = fixture["product"]
      require_hash(product, "product")
      require_keys(product, %w[key calibration path_days guarantee items_per_target], "product")
      error("product.path_days", "must be 30") unless product["path_days"] == 30
      error("product.guarantee", "must be false; practice cannot certify C2") unless product["guarantee"] == false
      error("product.items_per_target", "must be 12") unless product["items_per_target"] == 12

      presentation = fixture["presentation"]
      require_hash(presentation, "presentation")
      require_keys(presentation, %w[learner_fields reveal_fields forbidden_learner_fields], "presentation")
      forbidden = Array(presentation["forbidden_learner_fields"])
      required_forbidden = %w[answer correct_option hidden_answer solution]
      missing = required_forbidden - forbidden
      error("presentation.forbidden_learner_fields", "missing #{missing.join(', ')}") if missing.any?
      leaked_fields = Array(presentation["learner_fields"]) & forbidden
      error("presentation.learner_fields", "contains reveal-only field(s): #{leaked_fields.join(', ')}") if leaked_fields.any?
    end

    def validate_targets
      targets = Array(fixture["targets"])
      actual_keys = targets.filter_map { |target| target.is_a?(Hash) ? target["key"] : nil }
      error("targets", "must contain exactly #{TARGET_KEYS.join(', ')}") unless actual_keys.sort == TARGET_KEYS.sort

      targets.each_with_index do |target, index|
        path = "targets[#{index}]"
        unless target.is_a?(Hash)
          error(path, "must be a mapping")
          next
        end

        validate_target(target, path)
      end
    end

    def validate_target(target, path)
      require_keys(target, %w[key label modes source items], path)
      key = target["key"].to_s
      source = target["source"]
      validate_source(source, "#{path}.source")

      items = Array(target["items"])
      error("#{path}.items", "must contain at least 12 interview items") if items.length < 12
      seen_ids = []
      items.each_with_index do |item, index|
        item_path = "#{path}.items[#{index}]"
        validate_item(item, item_path, key, seen_ids)
      end
      duplicate_ids = seen_ids.group_by(&:itself).select { |_id, ids| ids.length > 1 }.keys
      error("#{path}.items", "duplicate id(s): #{duplicate_ids.join(', ')}") if duplicate_ids.any?

      modes = Array(target["modes"])
      if %w[dsa system_design].include?(key)
        error("#{path}.modes", "must include timed_simulation") unless modes.include?("timed_simulation")
        error("#{path}.timed_minutes", "must be 45") unless target["timed_minutes"] == 45
      elsif modes.include?("timed_simulation")
        error("#{path}.timed_minutes", "only DSA and system_design use the timed simulation")
      end

      if key == "system_design"
        links = Array(target["corpus_links"])
        error("#{path}.corpus_links", "must link system-design-estudos") unless links.any? { |link| link.is_a?(Hash) && link["repository"] == "system-design-estudos" }
      end
    end

    def validate_state_machine
      machine = fixture["state_machine"]
      require_hash(machine, "state_machine")
      states = Array(machine["states"])
      required_states = %w[idle active_recall feynman black_box feedback scheduled reattempt mastered]
      error("state_machine.states", "missing #{(required_states - states).join(', ')}") if (required_states - states).any?

      transitions = Array(machine["transitions"]).map { |edge| Array(edge) }
      required_transitions = [
        %w[idle active_recall],
        %w[active_recall feynman],
        %w[feynman feedback],
        %w[feedback scheduled],
        %w[feedback black_box],
        %w[black_box scheduled],
        %w[scheduled reattempt],
        %w[reattempt feynman],
        %w[reattempt mastered]
      ]
      required_transitions.each do |edge|
        error("state_machine.transitions", "missing #{edge.join(' -> ')}") unless transitions.include?(edge)
      end

      direct_mastery = transitions.select { |from, to| to == "mastered" && from != "reattempt" }
      error("state_machine.transitions", "mastery must only follow reattempt (found #{direct_mastery.map { |edge| edge.join(' -> ') }.join(', ')})") if direct_mastery.any?

      error("state_machine.terminal_states", "must contain mastered only") unless Array(machine["terminal_states"]) == [ "mastered" ]
      forbidden = Array(machine["forbidden_transitions"]).map { |edge| Array(edge) }
      %w[idle active_recall feedback].each do |state|
        error("state_machine.forbidden_transitions", "must forbid #{state} -> mastered") unless forbidden.include?([ state, "mastered" ])
      end
    end

    def validate_source(source, path)
      require_hash(source, path)
      require_keys(source, %w[repository path attribution], path)
      %w[repository path attribution].each do |key|
        error("#{path}.#{key}", "must be non-empty") if source[key].to_s.strip.empty?
      end
    end

    def validate_item(item, path, target_key, seen_ids)
      unless item.is_a?(Hash)
        error(path, "must be a mapping")
        return
      end

      require_keys(item, REQUIRED_ITEM_KEYS, path)
      id = item["id"].to_s
      seen_ids << id
      error("#{path}.id", "must start with #{target_key}-") unless id.start_with?("#{target_key}-")

      %w[prompt context answer rephrase extension source_ref].each do |key|
        error("#{path}.#{key}", "must be non-empty") if item[key].to_s.strip.empty?
      end
      error("#{path}.source_ref", "must point to the pack or linked corpus") unless %w[pack corpus].include?(item["source_ref"])

      distractors = Array(item["distractors"]).map { |value| value.to_s.strip }
      error("#{path}.distractors", "must contain at least two plausible choices") if distractors.length < 2
      error("#{path}.distractors", "must be unique") unless distractors.uniq.length == distractors.length
      if distractors.any? { |distractor| normalize(distractor) == normalize(item["answer"]) }
        error("#{path}.distractors", "must not contain the answer")
      end

      feedback = item["feedback"]
      require_hash(feedback, "#{path}.feedback")
      require_keys(feedback, FEEDBACK_KEYS, "#{path}.feedback")
      FEEDBACK_KEYS.each do |key|
        error("#{path}.feedback.#{key}", "must be non-empty") if feedback[key].to_s.strip.empty?
      end

      answer = normalize(item["answer"])
      public_text = %w[prompt context rephrase extension].map { |key| item[key] } + distractors
      if answer.empty? || public_text.any? { |value| normalize(value).include?(answer) }
        error("#{path}", "answer leaks into learner-visible text")
      end
      if Array(fixture.dig("presentation", "learner_fields")).include?("answer")
        error("presentation", "answer is exposed as a learner field")
      end
    end

    def validate_learning_loop
      loop = fixture["learning_loop"]
      require_hash(loop, "learning_loop")
      expected_stages = %w[active_recall feynman black_box leitner reattempt]
      error("learning_loop.stages", "must preserve closed-book recall through reattempt") unless Array(loop["stages"]) == expected_stages

      active_recall = loop["active_recall"]
      require_hash(active_recall, "learning_loop.active_recall")
      error("learning_loop.active_recall.closed_book", "must be true") unless active_recall["closed_book"] == true
      error("learning_loop.active_recall.answer_reveal_after_attempt", "must be true") unless active_recall["answer_reveal_after_attempt"] == true

      %w[feynman black_box].each do |stage|
        require_hash(loop[stage], "learning_loop.#{stage}")
        error("learning_loop.#{stage}.required_after_attempt", "must be true") if stage == "feynman" && loop[stage]["required_after_attempt"] != true
        error("learning_loop.#{stage}.required_after_error", "must be true") if stage == "black_box" && loop[stage]["required_after_error"] != true
      end

      leitner = loop["leitner"]
      require_hash(leitner, "learning_loop.leitner")
      intervals = (leitner["intervals_days"] || {}).transform_keys { |key| Integer(key) rescue key }
      error("learning_loop.leitner.intervals_days", "must be 1/2/4/7/14 for boxes 1..5") unless intervals == LEITNER_INTERVALS
      error("learning_loop.leitner.wrong_answer_box", "must reset to box 1") unless leitner["wrong_answer_box"] == 1
      error("learning_loop.leitner.correct_answer_advances_one_box", "must be true") unless leitner["correct_answer_advances_one_box"] == true

      reattempt = loop["reattempt"]
      require_hash(reattempt, "learning_loop.reattempt")
      error("learning_loop.reattempt.required_after_feedback", "must be true") unless reattempt["required_after_feedback"] == true
      error("learning_loop.reattempt.preserves_target", "must be true") unless reattempt["preserves_target"] == true

      mastery = loop["mastery"]
      require_hash(mastery, "learning_loop.mastery")
      error("learning_loop.mastery.score_at_least", "must be at least 8") unless mastery["score_at_least"].to_i >= 8
      error("learning_loop.mastery.attempts", "must require two attempts") unless mastery["attempts"].to_i >= 2
      error("learning_loop.mastery.separation_days", "must be about one week") unless mastery["separation_days"].to_i >= 7
    end

    def validate_persistence
      persistence = fixture["persistence"]
      require_hash(persistence, "persistence")
      required = {
        "session_fields" => %w[target_key mode started_at finished_at item_ids],
        "attempt_fields" => %w[target_key item_id attempt_number response_text score confidence created_at],
        "reflection_fields" => %w[feynman_text black_box_text created_at],
        "schedule_fields" => %w[leitner_box due_on last_result updated_at]
      }
      required.each do |name, keys|
        actual = Array(persistence[name])
        missing = keys - actual
        error("persistence.#{name}", "missing #{missing.join(', ')}") if missing.any?
      end
      reload = Array(persistence["reload_must_restore"])
      %w[target_key attempt_history leitner_box due_on].each do |key|
        error("persistence.reload_must_restore", "missing #{key}") unless reload.include?(key)
      end
    end

    def validate_adaptation
      adaptation = fixture["adaptation"]
      require_hash(adaptation, "adaptation")
      %w[target_preference_persists launcher_uses_saved_target next_item_uses_saved_target adaptation_must_not_change_target_silently].each do |key|
        error("adaptation.#{key}", "must be true") unless adaptation[key] == true
      end
      error("adaptation.weak_skill_signal", "must include error and confidence evidence") unless Array(adaptation["weak_skill_signal"]).include?("missed_attempts") && Array(adaptation["weak_skill_signal"]).include?("low_confidence")
    end

    def validate_accessibility
      accessibility = fixture["accessibility"]
      require_hash(accessibility, "accessibility")
      %w[semantic_controls visible_focus no_pointer_only_action].each do |key|
        error("accessibility.#{key}", "must be true") unless accessibility[key] == true
      end
      error("accessibility.minimum_touch_target_css_px", "must be at least 44") unless accessibility["minimum_touch_target_css_px"].to_i >= 44
      viewports = Array(accessibility["responsive_viewports"])
      error("accessibility.responsive_viewports", "must cover mobile, tablet, and desktop") unless viewports.length >= 3
    end

    def validate_health
      health = fixture["health"]
      require_hash(health, "health")
      %w[live_path content_path arcade_path expected_content_fields].each do |key|
        error("health.#{key}", "must be present") if health[key].nil? || (health[key].respond_to?(:empty?) && health[key].empty?)
      end
      %w[status study_documents content_bootstrapped latest_sync_status].each do |key|
        error("health.expected_content_fields", "missing #{key}") unless Array(health["expected_content_fields"]).include?(key)
      end
    end

    def require_hash(value, path)
      error(path, "must be a mapping") unless value.is_a?(Hash)
    end

    def require_keys(value, keys, path)
      return unless value.is_a?(Hash)

      missing = keys.reject { |key| value.key?(key) }
      error(path, "missing #{missing.join(', ')}") if missing.any?
    end

    def normalize(value)
      value.to_s.strip.downcase.gsub(/\s+/, " ")
    end

    def error(path, message)
      @errors << "#{path}: #{message}"
    end
  end
end
