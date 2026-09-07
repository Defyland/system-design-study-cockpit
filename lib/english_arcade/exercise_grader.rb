# frozen_string_literal: true

require_relative "text_tools"

module EnglishArcade
  # Grades a response against a server-owned authored item. The browser only
  # receives the exercise DTO; it never supplies correctness or an answer key.
  class ExerciseGrader
    AXES = %w[register hedging precision grammar pragmatics content].freeze

    class << self
      def grade(exercise, response: nil, response_text: nil, response_ms: nil, self_rating: nil, item:)
        new(exercise, item: item).grade(
          response: response, response_text: response_text, response_ms: response_ms, self_rating: self_rating
        )
      end
    end

    def initialize(exercise, item:)
      @exercise = stringify(exercise)
      @item = CorpusIndex.canonical_item(item)
    end

    def grade(response:, response_text:, response_ms:, self_rating:)
      case @exercise.fetch("type")
      when "meet" then result(correct: true, rating: 4)
      when "choose_best", "transfer" then grade_choice(response, response_ms)
      when "trap_axis" then grade_trap(response, response_ms)
      when "cloze" then grade_cloze(response, response_text)
      when "rebuild" then grade_rebuild(response)
      when "produce" then grade_production(response_text, self_rating)
      when "speak" then grade_production(response_text, self_rating, allow_self_rate: true)
      when "compress" then grade_compress(response_text, self_rating)
      when "feynman" then grade_feynman(response_text, self_rating)
      else raise ArgumentError, "unsupported Arena exercise type: #{@exercise["type"].inspect}"
      end
    end

    private

    def grade_choice(response, response_ms)
      selected = option_for(response)
      correct_text, distractors = choice_contract
      correct = selected && TextTools.normalize(selected["text"]) == TextTools.normalize(correct_text)
      timed = @exercise.dig("payload", "timed")
      rating = if correct
        timed ? timed_rating(response_ms, @exercise.dig("payload", "time_limit_ms")) : recognition_rating(response_ms)
      else
        1
      end
      trap = if correct
        nil
      else
        Array(distractors).find { |choice| TextTools.normalize(choice["text"]) == TextTools.normalize(selected && selected["text"]) }&.fetch("trap", "content")
      end
      result(correct: !!correct, rating: rating, trap_axis: trap, details: { "selected" => selected && selected["text"] })
    end

    def choice_contract
      if @exercise.fetch("type") == "transfer"
        variant_key = @exercise.dig("payload", "variant")
        variant = variants.fetch(variant_key)
        [ variant.fetch("best_answer"), Array(variant["distractors"]) ]
      else
        [ @item.fetch("best_answer"), Array(@item["distractors"]) ]
      end
    end

    def grade_trap(response, response_ms)
      expected = Array(@item["distractors"]).find do |choice|
        TextTools.normalize(choice["text"]) == TextTools.normalize(@exercise.dig("payload", "distractor"))
      end&.fetch("trap", "content")
      correct = response.to_s == expected.to_s
      result(correct: correct, rating: correct ? 3 : 1, trap_axis: correct ? expected : response.to_s)
    end

    def grade_cloze(response, response_text)
      submitted = hash_response(response, response_text)
      blanks = Array(@exercise.dig("payload", "blanks"))
      expected_tokens = TextTools.words(@item["best_answer"])
      wrong = blanks.filter_map do |blank|
        expected = expected_tokens[blank.fetch("start"), blank.fetch("length")].join(" ")
        actual = submitted[blank.fetch("id")]
        blank unless TextTools.normalize(actual) == TextTools.normalize(expected)
      end
      submitted_values = blanks.filter_map { |blank| submitted[blank.fetch("id")] }
      typed = submitted_values.any? { |value| !Array(blanks).flat_map { |blank| blank.fetch("chips") }.include?(value) }
      rating = if wrong.empty?
        typed ? 4 : 3
      elsif blanks.length >= 3 && wrong.length == 1
        2
      else
        1
      end
      result(correct: wrong.empty?, rating: rating, trap_axis: wrong.first&.fetch("axis", nil), details: { "wrong_blanks" => wrong.map { |blank| blank.fetch("id") } })
    end

    def grade_rebuild(response)
      chunks = Array(@exercise.dig("payload", "chunks"))
      selected = Array(response).map(&:to_s)
      ordered = selected.map { |entry| chunks.find { |chunk| chunk["id"] == entry } || chunks.find { |chunk| chunk["text"] == entry } }.compact
      expected = TextTools.clause_chunks(@item["best_answer"])
      actual = ordered.map { |chunk| chunk.fetch("text") }
      rating = if actual == expected
        3
      elsif adjacent_swap?(actual, expected)
        2
      else
        1
      end
      result(correct: rating == 3, rating: rating, trap_axis: rating == 3 ? nil : "order")
    end

    def grade_production(response_text, self_rating, allow_self_rate: false)
      if @exercise["type"] == "produce" && @item.key?("recall_check")
        return grade_resume_recall(response_text, self_rating)
      end

      similarity = TextTools.similarity(response_text, @item["best_answer"])
      anchors = production_anchors
      anchors_hit = anchors.count { |anchor| TextTools.normalize(response_text).include?(TextTools.normalize(anchor)) }
      ratio = anchors.empty? ? similarity : anchors_hit.fdiv(anchors.length)
      if allow_self_rate && TextTools.normalize(response_text).empty?
        rating = [ rating_value(self_rating), 3 ].min
        return result(
          correct: rating >= 3,
          rating: rating,
          details: { "similarity" => similarity, "anchors_hit" => 0, "anchors_total" => anchors.length, "self_rated" => true }
        )
      end

      cap = rating_cap(ratio)
      rating = [ rating_value(self_rating), cap ].min
      result(correct: rating >= 3, rating: rating, details: { "similarity" => similarity, "anchors_hit" => anchors_hit, "anchors_total" => anchors.length })
    end

    def grade_resume_recall(response_text, self_rating)
      check = @item.fetch("recall_check")
      groups = check.fetch("key_points")
      required = check.fetch("required_groups").to_i
      words = TextTools.word_count(response_text)
      response = " #{TextTools.normalize(response_text)} "
      hits = groups.count do |alternatives|
        alternatives.any? do |phrase|
          normalized = TextTools.normalize(phrase)
          !normalized.empty? && response.include?(" #{normalized} ")
        end
      end
      covered = required.positive? && hits >= required && words >= [ check.fetch("minimum_words").to_i, 15 ].max
      rating = covered ? [ rating_value(self_rating), 3 ].min : 1
      result(
        correct: rating >= 3, rating: rating,
        details: {
          "assessment_kind" => "phrase_recall", "word_count" => words,
          "key_points_hit" => hits, "key_points_required" => required,
          "unassessed" => %w[meaning grammar fluency pronunciation]
        }
      )
    end

    def grade_compress(response_text, self_rating)
      base = grade_production(response_text, self_rating)
      words = TextTools.word_count(response_text)
      cap = words.between?(15, 60) ? base.fetch("rating") : [ base.fetch("rating"), 2 ].min
      base.merge("correct" => cap >= 3, "rating" => cap, "details" => base.fetch("details").merge("word_count" => words))
    end

    def grade_feynman(response_text, self_rating)
      has_explanation = !TextTools.normalize(response_text).empty?
      rating = has_explanation ? [ rating_value(self_rating), 3 ].min : 1
      result(
        correct: has_explanation && rating >= 3,
        rating: rating,
        details: { "word_count" => TextTools.word_count(response_text) }
      )
    end

    def production_anchors
      tokens = TextTools.words(@item["best_answer"])
      slots = Array(@exercise.dig("payload", "anchor_slots"))
      return slots.filter_map { |slot| tokens[slot["start"].to_i, slot["length"].to_i]&.join(" ") } if slots.any?

      # Backward-compatible fallback for an in-flight lesson created before
      # anchor slot positions were added to the public production DTO.
      tokens.each_cons(2).map(&:join).reject { |phrase| TextTools.words(phrase).all? { |word| TextTools::STOPWORDS.include?(word) } }.first(4)
    end

    def result(correct:, rating:, trap_axis: nil, details: {})
      {
        "correct" => !!correct,
        "rating" => rating.to_i.clamp(1, 4),
        "trap_axis" => present_or_nil(trap_axis),
        "details" => details
      }.compact
    end

    def option_for(response)
      Array(@exercise.dig("payload", "options")).find { |option| option["id"] == response.to_s }
    end

    def variants
      authored = stringify(@item["variants"] || {})
      return authored unless authored.empty?

      raise ArgumentError, "EnglishArcadeAttemptContract is required for transfer grading" unless defined?(EnglishArcadeAttemptContract)

      EnglishArcadeAttemptContract.variants_for(@item)
    end

    def hash_response(response, response_text)
      raw = response.is_a?(Hash) ? response : response_text
      raw.is_a?(Hash) ? stringify(raw) : {}
    end

    def recognition_rating(_response_ms)
      # Browser timing is useful telemetry, but it is not authoritative enough
      # to increase or reduce a learner's SRS rating.
      3
    end

    def timed_rating(_response_ms, _limit)
      3
    end

    def adjacent_swap?(actual, expected)
      return false unless actual.length == expected.length

      mismatches = actual.each_index.select { |index| actual[index] != expected[index] }
      return false unless mismatches.length == 2 && mismatches.last == mismatches.first + 1

      actual[mismatches.first] == expected[mismatches.last] && actual[mismatches.last] == expected[mismatches.first]
    end

    def rating_cap(ratio)
      return 4 if ratio >= 0.99
      return 3 if ratio >= 0.66
      return 2 if ratio >= 0.34

      1
    end

    def rating_value(value)
      value.to_i.clamp(1, 4)
    end

    def milliseconds(value)
      value.to_f.negative? ? 0.0 : value.to_f
    end

    def present_or_nil(value)
      text = value.to_s.strip
      text.empty? ? nil : text
    end

    def stringify(value)
      case value
      when Hash then value.each_with_object({}) { |(key, nested), result| result[key.to_s] = stringify(nested) }
      when Array then value.map { |nested| stringify(nested) }
      else value
      end
    end
  end
end
