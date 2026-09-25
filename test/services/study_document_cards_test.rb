require "test_helper"

class StudyDocumentCardsTest < ActiveSupport::TestCase
  test "all text survives sectioning including headings inside fenced code" do
    text = <<~MD
      # Ruby notes

      ## Closures

      I choose a lambda for an explicit return boundary.

      ```ruby
      ### This is a code comment, not a section
      -> { 42 }
      ```

      ### Follow-up

      **Q: What happens on return?**

      I return from the lambda.
    MD
    doc = StudyDocument.new(id: 123, kind: "reference_document", title: "Ruby notes", source_path: "notes/ruby.md", body_markdown: text, metadata: {})
    cards = StudyDocumentCards.new(documents: [ doc ]).cards
    assert_equal text, cards.map { |card| card[:answer_markdown] }.join
    assert_equal 2, cards.size
    assert_includes cards.first[:answer_markdown], "### This is a code comment"
    assert_equal "What happens on return?", cards.last[:prompt]
    assert cards.all? { |card| card[:topics].include?("ruby") }
    original_keys = cards.map { |card| card[:id] }
    doc.body_markdown += "\n## Added section\n\nMore information.\n"
    assert_equal original_keys, StudyDocumentCards.new(documents: [ doc ]).cards.take(2).map { |card| card[:id] }
  end
end
