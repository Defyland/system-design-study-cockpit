# frozen_string_literal: true

require "digest"
require_relative "corpus_index"
require_relative "text_tools"

module EnglishArcade
  # Materializes only learner-safe exercise data from an authored card. Answer
  # identity is intentionally not included: ExerciseGrader receives the same
  # server-owned item again when a result is submitted.
  class ExerciseFactory
    class UnsupportedExercise < ArgumentError; end

    HEDGE_PHRASES = [
      "i would not", "rather than", "roughly", "perhaps", "before",
      "unless", "whether", "i would", "because"
    ].freeze
    FORBIDDEN_KEYS = %w[critical_thinking provenance sources black_box variants].freeze

    def initialize(corpus_index:)
      @corpus_index = corpus_index
    end

    def supported?(item, stage:, slot: 0)
      build(item, stage: stage, slot: slot)
      true
    rescue UnsupportedExercise
      false
    end

    def build(item, stage:, slot: 0, content_version: nil, timed: false, boss: false, occurrence: nil)
      item = CorpusIndex.canonical_item(item)
      stage = normalize_stage(stage)
      type, payload = materialize(item, stage, slot: slot, timed: timed)
      envelope = {
        "exercise_id" => exercise_id(item, stage, slot, content_version, boss: boss, occurrence: occurrence),
        "card_key" => item.fetch("id"),
        "target" => item.fetch("target"),
        "topic" => item["topic"].to_s,
        "stage" => stage,
        "type" => type,
        "prompt" => item["prompt"].to_s,
        "context" => item["context"].to_s,
        "payload" => payload
      }
      assert_safe!(envelope)
      envelope
    end

    # Server-side reveal generated after a result. It is separate from the
    # initial JSON exercise so a learner cannot inspect the answer in advance.
    def reveal(item, selected_text: nil, selected_texts: nil, variant_key: nil)
      item = CorpusIndex.canonical_item(item)
      item = variant_item(item, variant_key) unless variant_key.to_s.strip.empty?
      selected_values = Array(selected_texts)
      selected_values = [ selected_text ] if selected_values.empty?
      selected = Array(item["distractors"]).find do |choice|
        selected_values.any? { |value| TextTools.normalize(choice["text"]) == TextTools.normalize(value) }
      end
      selected ||= Array(item["distractors"]).find do |choice|
        cloze_spans(item).any? do |span|
          replacement = authored_replacement(item, choice, span)
          replacement && selected_values.any? { |value| TextTools.normalize(replacement) == TextTools.normalize(value) }
        end
      end
      {
        "best_answer" => item["best_answer"].to_s,
        "feedback" => stringify(item["feedback"] || {}),
        "why_wrong" => selected && selected["why_wrong"].to_s,
        "trap_axis" => selected && selected["trap"].to_s,
        "pt_help" => present_or_nil(item["pt_help"])
      }.compact
    end

    private

    def materialize(item, stage, slot:, timed:)
      case stage
      when "meet"
        [ "meet", { "instruction" => "Read the answer, then continue when it is clear." } ]
      when "recognize"
        [ "choose_best", choose_payload(item, slot: slot, timed: timed) ]
      when "trap"
        [ "trap_axis", trap_payload(item, slot: slot) ]
      when "cloze"
        [ "cloze", cloze_payload(item, slot: slot) ]
      when "rebuild"
        [ "rebuild", rebuild_payload(item, slot: slot) ]
      when "produce"
        [ "produce", production_payload(item) ]
      when "transfer"
        [ "transfer", transfer_payload(item, slot: slot) ]
      when "speak", "compress", "feynman"
        [ stage, satellite_payload(item, stage) ]
      else
        raise ArgumentError, "unsupported Arena stage: #{stage.inspect}"
      end
    end

    def choose_payload(item, slot:, timed:)
      options = [ item["best_answer"], *Array(item["distractors"]).map { |choice| choice["text"] } ]
      ordered = deterministic_shuffle(options, seed_for(item, "recognize", slot))
      {
        "options" => ordered.each_with_index.map { |text, index| { "id" => "choice-#{index + 1}", "text" => text.to_s } },
        "timed" => !!timed,
        "time_limit_ms" => timed ? 15_000 : nil
      }.compact
    end

    def trap_payload(item, slot:)
      choices = Array(item["distractors"])
      raise ArgumentError, "#{item.fetch("id")} has no distractor for trap stage" if choices.empty?

      distractor = choices.fetch(slot % choices.length)
      {
        "distractor" => distractor.fetch("text").to_s,
        "axes" => deterministic_shuffle(%w[register hedging precision grammar pragmatics content], seed_for(item, "trap", slot))
      }
    end

    def cloze_payload(item, slot:)
      spans = cloze_spans(item).first(cloze_count(item["best_answer"])).map do |span|
        [ span, chip_candidates(item, span) ]
      end
      raise UnsupportedExercise, "#{item.fetch("id")} cannot supply two safe cloze spans" if spans.length < 2

      tokens = TextTools.display_tokens(item["best_answer"])
      blanks = spans.sort_by { |span, _candidates| span[:start] }.each_with_index.map do |(span, candidates), index|
        {
          "id" => "blank-#{index + 1}",
          "start" => span[:start],
          "length" => span[:length],
          "axis" => span[:axis],
          "input_mode" => candidates.length >= 2 ? "chips" : "typed",
          "chips" => candidates.length >= 2 ? deterministic_shuffle(candidates.first(4), seed_for(item, "cloze:#{index}", slot)) : []
        }
      end
      {
        "tokens" => redacted_tokens(tokens, blanks),
        "blanks" => blanks
      }
    end

    def rebuild_payload(item, slot:)
      chunks = TextTools.clause_chunks(item["best_answer"])
      raise ArgumentError, "#{item.fetch("id")} cannot supply three rebuild chunks" if chunks.length < 3

      ordered = chunks.each_with_index.map { |text, index| { "id" => "chunk-#{index + 1}", "text" => text } }
      { "chunks" => deterministic_shuffle(ordered, seed_for(item, "rebuild", slot)) }
    end

    def transfer_payload(item, slot:)
      variant_key = slot.to_i.zero? ? "follow_up" : "delayed_variant"
      variant = variant_for(item, variant_key)
      unless usable_transfer_variant?(variant_key, variant)
        raise UnsupportedExercise, "#{item.fetch("id")} has no usable #{variant_key} variant"
      end

      options = [ variant["best_answer"], *Array(variant["distractors"]).map { |choice| choice.is_a?(Hash) ? choice["text"] : choice } ]
      {
        "variant" => variant_key,
        "prompt" => variant["prompt"].to_s,
        "options" => deterministic_shuffle(options, seed_for(item, "transfer:#{slot}", slot)).each_with_index.map do |text, index|
          { "id" => "choice-#{index + 1}", "text" => text.to_s }
        end
      }
    end

    def satellite_payload(item, stage)
      case stage
      when "speak" then { "optional" => true, "instruction" => "Listen to the model and repeat aloud. A transcript is optional; self-rating is capped at good." }
      when "compress"
        prompt = item.dig("compression", "prompt").to_s.strip
        raise UnsupportedExercise, "#{item.fetch('id')} has no authored compression prompt" if prompt.empty?

        { "prompt" => prompt, "cue" => item.dig("recall", "active_recall_cue").to_s }
      when "feynman"
        payload = stringify(item["feynman"] || {}).slice("concept", "explain_to", "constraint", "self_check")
        raise UnsupportedExercise, "#{item.fetch('id')} has no authored Feynman prompt" if payload.values_at("concept", "explain_to", "constraint").any? { |value| value.to_s.strip.empty? }

        payload
      end
    end

    def production_payload(item)
      slots = cloze_spans(item).first(cloze_count(item["best_answer"])).map do |span|
        { "start" => span[:start], "length" => span[:length] }
      end
      { "cue" => item.dig("recall", "active_recall_cue").to_s, "anchor_slots" => slots }
    end

    def cloze_spans(item)
      selected = []
      transfer_spans(item).each { |span| take_span(selected, span) unless TextTools.span_crosses_punctuation?(item["best_answer"], span[:start], span[:length]) }
      hedge_limit = selected.empty? ? 2 : 1
      hedge_spans(item).first(hedge_limit).each do |span|
        take_span(selected, span) unless TextTools.span_crosses_punctuation?(item["best_answer"], span[:start], span[:length])
      end
      @corpus_index.distinctive_spans(item, limit: 8).each do |span|
        next if TextTools.span_crosses_punctuation?(item["best_answer"], span[:start], span[:length])

        take_span(selected, span.merge(axis: "precision", alternatives: []))
      end
      selected.sort_by { |span| span[:start] }
    end

    def transfer_spans(item)
      grammar = Array(item["distractors"]).select { |choice| choice["trap"] == "grammar" }
      grammar.flat_map do |choice|
        quoted_transfer_segments(item["best_answer"], choice).yield_self do |quoted|
          quoted.any? ? quoted : TextTools.diff_segments(item["best_answer"], choice["text"]).filter_map do |segment|
            next unless segment[:length].between?(1, 6)
            next unless TextTools.normalize(choice["why_wrong"]).include?(TextTools.normalize(segment[:alternative]))

            segment.merge(axis: "grammar", alternatives: [ segment[:alternative] ])
          end
        end
      end.sort_by do |span|
        phrase = Array(span[:alternatives]).join(" ")
        comparative = phrase.match?(/\b(?:more|less|most)\b/) ? 0 : 1
        [ comparative, -phrase.length, span[:start] ]
      end
    end

    # Grammar diagnoses often quote only the erroneous phrase, while LCS may
    # retain a coincidental common word inside it ("small" in the Go item).
    # Reconstruct the surrounding best-answer region from anchors on both sides
    # of that quoted phrase rather than treating the shared word as a boundary.
    def quoted_transfer_segments(best_answer, choice)
      best = TextTools.words(best_answer)
      alternative = TextTools.words(choice["text"])
      diagnosis = TextTools.normalize(choice["why_wrong"])
      quoted = choice["why_wrong"].to_s.scan(/[\"“]([^\"”]+)[\"”]/).flatten.map { |phrase| TextTools.normalize(phrase) }
      anchors = TextTools.lcs_pairs(best_answer, choice["text"])
      alternative.each_index.flat_map do |start|
        1.upto([ 6, alternative.length - start ].min).filter_map do |length|
          phrase = alternative[start, length].join(" ")
          next unless phrase.length >= 4 && diagnosis.include?(phrase)
          next if quoted.any? && !quoted.include?(phrase)

          before = anchors.reverse.find { |_left, right| right < start }
          after = anchors.find { |_left, right| right >= start + length }
          next unless before && after

          best_start = before.first + 1
          best_length = after.first - best_start
          next unless best_length.positive? && best_length <= 7

          { start: best_start, length: best_length, axis: "grammar", alternatives: [ phrase ] }
        end
      end.uniq { |span| [ span[:start], span[:length], span[:alternatives] ] }
    end

    def hedge_spans(item)
      tokens = TextTools.words(item["best_answer"])
      HEDGE_PHRASES.filter_map do |phrase|
        phrase_tokens = TextTools.words(phrase)
        start = tokens.each_cons(phrase_tokens.length).find_index { |window| window == phrase_tokens }
        next unless start

        { start: start, length: phrase_tokens.length, axis: "hedging", alternatives: [] }
      end
    end

    def take_span(selected, span)
      start = span[:start]
      finish = start + span[:length] - 1
      return if selected.any? { |current| (start - current[:start]).abs < 6 || (start..finish).cover?(current[:start]) }

      selected << span
    end

    def chip_candidates(item, span)
      expected = TextTools.words(item["best_answer"])[span[:start], span[:length]].join(" ")
      own = Array(item["distractors"]).filter_map { |choice| authored_replacement(item, choice, span) }
      ([ expected ] + own).filter_map do |candidate|
        value = candidate.to_s.strip
        next if value.empty?
        next unless TextTools.word_count(value) == span[:length]
        next if value != expected && value.match?(/[^A-Za-z0-9\s'’]/)
        next if value != expected && !TextTools.informative_phrase?(value)

        value
      end.uniq { |value| TextTools.normalize(value) }
    end

    # Only accept the literal authored replacement for this exact best-answer
    # interval. If no distractor changes this span cleanly, the exercise uses a
    # typed blank instead of manufacturing a chip bank.
    def authored_replacement(item, choice, span)
      segment = TextTools.diff_segments(item["best_answer"], choice["text"]).find do |candidate|
        candidate[:start] == span[:start] &&
          candidate[:length] == span[:length] &&
          same_length_candidate?(candidate[:alternative], span[:length])
      end
      segment && segment[:alternative]
    end

    def redacted_tokens(tokens, blanks)
      start_map = blanks.to_h { |blank| [ blank["start"], blank ] }
      result = []
      index = 0
      while index < tokens.length
        blank = start_map[index]
        if blank
          first = tokens[index].to_s
          last = tokens[index + blank.fetch("length") - 1].to_s
          prefix = first[/\A[^A-Za-z0-9'’]*/].to_s
          suffix = last[/[^A-Za-z0-9'’]*\z/].to_s
          result << "#{prefix}[#{blank.fetch("id")}]#{suffix}"
          index += blank.fetch("length")
        else
          result << tokens[index]
          index += 1
        end
      end
      result
    end

    def cloze_count(answer)
      count = TextTools.word_count(answer)
      count <= 40 ? 2 : count <= 70 ? 3 : 4
    end

    def exercise_id(item, stage, slot, content_version, boss:, occurrence:)
      version = content_version.to_s.empty? ? item["version"].to_s : content_version.to_s
      digest = Digest::SHA256.hexdigest(version)[0, 8]
      suffix = [ slot, occurrence, ("boss" if boss) ].compact.join(":")
      "#{item.fetch("id")}:#{stage}:#{suffix}:#{digest}"
    end

    def seed_for(item, purpose, slot)
      Digest::SHA256.hexdigest([ item.fetch("id"), item["version"], purpose, slot ].join("\u0000"))
    end

    def deterministic_shuffle(values, seed)
      Array(values).sort_by.with_index { |value, index| Digest::SHA256.hexdigest("#{seed}\u0000#{index}\u0000#{value}") }
    end

    def normalize_stage(stage)
      { "spot_the_trap" => "trap", "choose_best" => "recognize" }.fetch(stage.to_s, stage.to_s)
    end

    def assert_safe!(envelope)
      forbidden = deep_keys(envelope).find { |key| FORBIDDEN_KEYS.include?(key) }
      raise ArgumentError, "unsafe Arena payload includes #{forbidden}" if forbidden
    end

    def deep_keys(value)
      case value
      when Hash then value.flat_map { |key, nested| [ key.to_s, *deep_keys(nested) ] }
      when Array then value.flat_map { |nested| deep_keys(nested) }
      else []
      end
    end

    def present_or_nil(value)
      text = value.to_s.strip
      text.empty? ? nil : text
    end

    def variant_item(item, variant_key)
      variant = variant_for(item, variant_key)
      item.merge(
        "best_answer" => variant["best_answer"].to_s,
        "distractors" => Array(variant["distractors"]),
        "feedback" => variant["feedback"] || item["feedback"]
      )
    end

    def variant_for(item, variant_key)
      variant = stringify(item.dig("variants", variant_key) || {})
      variant = EnglishArcadeAttemptContract.variants_for(item)[variant_key] if variant.empty? && defined?(EnglishArcadeAttemptContract)
      raise UnsupportedExercise, "#{item.fetch("id")} has no #{variant_key} variant" unless variant.is_a?(Hash) && !variant.empty?

      variant
    end

    def usable_transfer_variant?(variant_key, variant)
      return false unless variant.is_a?(Hash)
      return false if variant["best_answer"].to_s.strip.empty?
      return false unless Array(variant["distractors"]).length >= 2
      return false if variant_key.to_s == "delayed_variant" && TextTools.normalize(variant["best_answer"]).start_with?("i would keep the facts that remain supported about")

      true
    end

    def same_length_candidate?(candidate, length)
      TextTools.word_count(candidate) == length &&
        !candidate.to_s.match?(/[^A-Za-z0-9\s'’]/) &&
        TextTools.informative_phrase?(candidate)
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
