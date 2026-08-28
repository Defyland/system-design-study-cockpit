# frozen_string_literal: true

require "json"

module EnglishArcadeVoice
  # Produces the only instructions allowed into a Realtime session. The card is
  # resolved server-side before this object is created; callers never provide
  # free-form context or instructions.
  class SessionPrompt
    attr_reader :card

    def self.for(card)
      new(card).call
    end

    def initialize(card)
      @card = card
    end

    def call
      sections = [
        "You are the English Arcade rehearsal coach.",
        "This is answered-question rehearsal, not an assessment or certification.",
        "Treat the authored question, best answer, reasoning, trade-offs, and source limits below as the truth for this card.",
        "Use first-person safe interview language such as 'I would', 'assuming', and 'I would verify'.",
        "After the learner speaks, give concise, useful observations about clarity, fluency, pace, grammar, and relevance.",
        "Pronunciation observations must be cautious and limited to what the audio supports.",
        "Never claim objective CEFR scoring, a guaranteed pronunciation or phonetic result, or certainty the card does not provide.",
        "Never invent facts or provenance and never manufacture missing content.",
        "When a factual point is uncertain, direct the learner back to the visible card sources.",
        "Keep the authored answer and its caveats intact; do not replace them with generic advice.",
        "",
        "AUTHORITATIVE CARD MATERIAL",
        "Question: #{text(card_value(:prompt))}",
        "Context: #{text(card_value(:context))}",
        "Authored best answer: #{text(card_value(:answer_text))}",
        "Authored reasoning and trade-offs: #{text(reasoning_and_tradeoffs)}",
        "Source limits: #{text(source_limits)}"
      ]

      sections.join("\n")
    end

    alias to_s call

    private

    def card_value(name)
      return card.public_send(name) if card.respond_to?(name)
      return card[name] if card.respond_to?(:[]) && (card.key?(name) rescue false)
      return card[name.to_s] if card.respond_to?(:[]) && (card.key?(name.to_s) rescue false)

      nil
    end

    def reasoning_and_tradeoffs
      critical = card_value(:critical_thinking)
      critical = card_value(:variant_contract).to_h["critical_thinking"] if critical.blank?
      critical = card_value(:variant_contract).to_h[:critical_thinking] if critical.blank?
      return critical if critical.present? && !critical.is_a?(Hash)

      if critical.is_a?(Hash)
        selected = critical.deep_stringify_keys.slice(
          "problem_frame", "claim_map", "comparison", "failure_probe", "evidence_check", "certainty"
        )
        return JSON.generate(selected) if selected.present?
      end

      "No additional authored reasoning or trade-off was provided on this card."
    end

    def source_limits
      provenance = card_value(:provenance)
      provenance = provenance.to_h.deep_stringify_keys if provenance.respond_to?(:to_h)
      limits = []
      if provenance.is_a?(Hash)
        Array(provenance["confirmation_required"]).filter_map { |item| item.to_s.strip.presence }.each do |item|
          limits << "Confirmation required: #{item}"
        end
        evidence_class = provenance["evidence_class"].to_s.strip
        limits << "Evidence class: #{evidence_class}" if evidence_class.present?
      end

      confidentiality = provenance["confidentiality"] if provenance.is_a?(Hash)
      if confidentiality.is_a?(Hash)
        level = confidentiality["level"].to_s.strip
        limits << "Confidentiality level: #{level}" if level.present?
      end

      source_count = Array(card_value(:sources)).compact.length
      if source_count.positive?
        limits << "Visible authored source pointers exist (count: #{source_count})."
      else
        limits << "No source limit was provided; use only the visible card material. No visible authored source pointers were provided."
      end
      limits.any? ? limits.join(" | ") : "No source limit was provided; use only the visible card material."
    end

    def text(value)
      value.to_s.strip.presence || "[not provided by the authored card]"
    end
  end
end
