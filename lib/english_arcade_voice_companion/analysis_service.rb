# frozen_string_literal: true

module EnglishArcadeVoiceCompanion
  class AnalysisService
    FIELDS = %w[
      summary clarity fluency pace grammar relevance pronunciation limitations first_person_example
    ].freeze
    MAX_TRANSCRIPT_BYTES = 64 * 1024

    class InvalidInput < StandardError; end
    class Unavailable < StandardError; end

    attr_reader :codex

    def initialize(codex:)
      @codex = codex
    end

    def call(question:, answer:, context:, transcript:)
      values = {
        question: question,
        answer: answer,
        context: context,
        transcript: transcript
      }
      values.each do |name, value|
        raise InvalidInput unless value.is_a?(String) && value.bytesize <= (name == :transcript ? MAX_TRANSCRIPT_BYTES : Prompt::MAX_FIELD_BYTES)
      end
      raise InvalidInput if values[:question].strip.empty? || values[:answer].strip.empty? || values[:transcript].strip.empty?

      result = codex.analyze(**values)
      normalize(result)
    rescue CodexAppServerClient::Unavailable
      raise Unavailable
    end

    private

    def normalize(result)
      hash = result.is_a?(Hash) ? result : {}
      output = FIELDS.to_h do |field|
        value = hash[field] || hash[field.to_sym]
        raise InvalidInput unless value.is_a?(String)

        [ field, value.strip[0, 2 * 1024] ]
      end
      output
    end
  end
end
