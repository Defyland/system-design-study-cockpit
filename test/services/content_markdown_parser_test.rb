require "test_helper"

class ContentMarkdownParserTest < ActiveSupport::TestCase
  test "extracts title metadata blocks and checkpoint answers" do
    markdown = <<~MARKDOWN
      # Chapter 03 - Idempotent Writes

      ## Study Context

      - `Study Order`: `03/14` - `Fase 1 - Base forte`
      - `Caso real principal`: [Stripe - Idempotent Payments](../real-world-cases/stripe/README.md)
      - `Area principal`: [03 - Filas e Consistencia](../areas/03/README.md)

      ## Onde Isso Aparece Antes da Teoria

      Pagamentos e pedidos.

      ## First Principles Design Pass

      - `Requirement Less Dumb`: precisa mesmo cobrar agora?
      - `Delete`: remova o retry automatico ate provar idempotencia.

      ### Fixacao Relampago

      - `Pergunta`: quando usar idempotency key?
      - `Resposta com as suas palavras`: quando retry pode duplicar efeito.
      - `Resposta ruim que parece boa`: retry resolve.
      - `Troque por isto`: proteja o efeito antes do retry.
    MARKDOWN

    parsed = Content::MarkdownParser.new.parse(
      kind: "chapter",
      source_path: "chapters/chapter-03-idempotent-writes.md",
      body_markdown: markdown
    )

    assert_equal "chapter-03-idempotent-writes", parsed.fetch(:slug)
    assert_equal "Chapter 03 - Idempotent Writes", parsed.fetch(:title)
    assert_equal 3, parsed.fetch(:position)
    assert_equal "Fase 1 - Base forte", parsed.fetch(:phase)
    assert_equal "Stripe - Idempotent Payments", parsed.fetch(:metadata).fetch("primary_case")
    assert parsed.fetch(:blocks).any?
    assert parsed.fetch(:blocks).any? { |block| block.fetch(:content_markdown).include?("First Principles Design Pass") }
    assert parsed.fetch(:blocks).none? { |block| block.fetch(:content_markdown).include?("Fixacao Relampago") }
    assert parsed.fetch(:blocks).none? { |block| block.fetch(:content_markdown).include?("retry resolve") }

    checkpoint = parsed.fetch(:checkpoints).first
    assert_equal 1, parsed.fetch(:checkpoints).size
    assert_equal "Fixacao Relampago", checkpoint.fetch(:source_label)
    assert_equal "quando usar idempotency key?", checkpoint.fetch(:prompt)
    assert_equal "quando retry pode duplicar efeito.", checkpoint.fetch(:good_answer)
    assert_equal "retry resolve.", checkpoint.fetch(:bad_answer)
    assert_equal "proteja o efeito antes do retry.", checkpoint.fetch(:correction)
  end

  test "uses parent directory as slug for real world case readmes" do
    parsed = Content::MarkdownParser.new.parse(
      kind: "real_world_case",
      source_path: "real-world-cases/05-product-scenarios/spotify-personalization/README.md",
      body_markdown: "# Spotify Personalization\n\nCaso real."
    )

    assert_equal "spotify-personalization", parsed.fetch(:slug)
    assert_equal "Spotify Personalization", parsed.fetch(:title)
    assert_equal 0, parsed.fetch(:position)
  end

  test "prefixes side track slugs with the track id to avoid collisions" do
    chapter = Content::MarkdownParser.new.parse(
      kind: "side_track_chapter",
      source_path: "areas/08-sistemas-ia/llm-foundations/chapters/01-tokens-embeddings-and-training-windows.md",
      body_markdown: "# Tokens, Embeddings and Training Windows\n\nTexto."
    )
    review_card = Content::MarkdownParser.new.parse(
      kind: "side_track_review_card",
      source_path: "areas/08-sistemas-ia/llm-foundations/reviews/cards/01-tokens-embeddings-and-training-windows.md",
      body_markdown: "# Recall\n\nTexto."
    )
    reference = Content::MarkdownParser.new.parse(
      kind: "side_track_reference",
      source_path: "areas/08-sistemas-ia/llm-foundations/source-map.md",
      body_markdown: "# Source Map\n\nTexto."
    )

    assert_equal "llm-foundations-01-tokens-embeddings-and-training-windows", chapter.fetch(:slug)
    assert_equal "llm-foundations-01-tokens-embeddings-and-training-windows", review_card.fetch(:slug)
    assert_equal "llm-foundations-source-map", reference.fetch(:slug)
    assert_equal 1, chapter.fetch(:position)
    assert_equal 0, reference.fetch(:position)
  end

  test "uses the full source path as slug for reference documents to avoid README and notes collisions" do
    readme = Content::MarkdownParser.new.parse(
      kind: "reference_document",
      source_path: "areas/01-metodo-e-entrevistas/README.md",
      body_markdown: "# Metodo e Entrevistas\n\nTexto."
    )
    notes = Content::MarkdownParser.new.parse(
      kind: "reference_document",
      source_path: "areas/02-dados-e-armazenamento/notes.md",
      body_markdown: "# Notes\n\nTexto."
    )

    assert_equal "areas-01-metodo-e-entrevistas-README", readme.fetch(:slug)
    assert_equal "areas-02-dados-e-armazenamento-notes", notes.fetch(:slug)
    assert_equal "Metodo e Entrevistas", readme.fetch(:title)
    assert_equal "Notes", notes.fetch(:title)
  end
end
