# frozen_string_literal: true

require "set"
require_relative "text_tools"

module EnglishArcade
  # Read-only index over authored pack items. It supplies distinctive spans and
  # same-target chip candidates; it never changes or augments the corpus.
  class CorpusIndex
    attr_reader :items

    def initialize(items)
      @items = Array(items).map { |item| self.class.canonical_item(item) }.freeze
      @by_target = @items.group_by { |item| item.fetch("target").to_s }.freeze
      @document_frequency = build_document_frequency.freeze
    end

    def items_for(target)
      @by_target.fetch(target.to_s, [])
    end

    def idf(token)
      Math.log((@items.length + 1).fdiv(@document_frequency.fetch(token.to_s, 0) + 1)) + 1.0
    end

    def distinctive_spans(item, limit: 4)
      item = self.class.canonical_item(item)
      tokens = TextTools.words(item["best_answer"])
      scores = tokens.each_cons(2).with_index.filter_map do |pair, start|
        next if pair.any? { |token| TextTools::STOPWORDS.include?(token) }

        bonus = bonus_for(pair.join(" "), item)
        [ start, pair.length, pair.join(" "), pair.sum { |token| idf(token) } + bonus ]
      end
      scores.sort_by { |start, _length, text, score| [ -score, start, text ] }
        .first(limit).map { |start, length, text, _score| { start: start, length: length, text: text } }
    end

    def same_length_candidates(item, length:, exclude: [])
      item = self.class.canonical_item(item)
      excluded = Set.new(Array(exclude).map { |value| TextTools.normalize(value) })
      source_items = items_for(item["target"]).reject { |other| other["id"] == item["id"] }
      source_items.flat_map do |other|
        TextTools.words(other["best_answer"]).each_cons(length).map { |tokens| tokens.join(" ") }
      end.reject { |candidate| excluded.include?(TextTools.normalize(candidate)) }
        .uniq { |candidate| TextTools.normalize(candidate) }
    end

    private

    class << self
      # SessionBuilder exposes normalized cards, whereas pack tests use raw
      # YAML items. This is the one compatibility boundary between them; all
      # learning logic below sees the authored item vocabulary.
      def canonical_item(item)
        raw = stringify(item)
        initial = stringify(raw.dig("variants", "initial") || {})
        choices = Array(raw["choices"])
        correct_choice = raw["correct_choice"].to_s
        distractors = raw["distractors"] || initial["distractors"] || choices.reject { |choice| choice["id"].to_s == correct_choice }.map do |choice|
          { "text" => choice["text"], "trap" => "content", "why_wrong" => "This alternative is weaker for the authored context." }
        end
        raw.merge(
          "id" => raw["id"] || raw["key"],
          "target" => raw["target"],
          "best_answer" => raw["best_answer"] || raw["answer_text"] || initial["best_answer"],
          "distractors" => stringify(distractors),
          "feedback" => raw["feedback"] || initial["feedback"] || {},
          "context" => raw["context"] || initial["context"],
          "prompt" => raw["prompt"] || initial["prompt"]
        )
      end

      private

      def stringify(value)
        case value
        when Hash then value.each_with_object({}) { |(key, nested), result| result[key.to_s] = stringify(nested) }
        when Array then value.map { |nested| stringify(nested) }
        else value
        end
      end
    end
    def build_document_frequency
      @items.each_with_object(Hash.new(0)) do |item, result|
        TextTools.words(item["best_answer"]).uniq.each { |token| result[token] += 1 }
      end
    end

    def bonus_for(span, item)
      haystack = [ item.dig("recall", "active_recall_cue"), item.dig("feynman", "concept"), item["topic"] ].compact.join(" ")
      TextTools.normalize(haystack).include?(span) ? 0.75 : 0.0
    end
  end
end
