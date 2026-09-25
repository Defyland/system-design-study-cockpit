# Run with bin/rails runner script/verify_study_card_catalog.rb.
# Audits the real imported corpus; no fixtures or generated expected answers.
require "json"

catalog = StudyCardCatalog.new
cards = catalog.cards
documents = StudyDocument.ordered.to_a
library_cards = cards.select { |card| card[:document_id] }
errors = []
errors << "Duplicate card IDs" unless cards.map { |card| card[:id] }.uniq.size == cards.size
by_document = library_cards.group_by { |card| card[:document_id] }
documents.each do |document|
  original = by_document.fetch(document.id, []).map { |card| card[:answer_markdown] }.join
  errors << "Text lost: #{document.source_path}" unless original == document.body_markdown
end
content = ArcadeContent.new
interview_count = 0
content.targets.each do |target|
  content.items_for(target).each do |item|
    [ [ "initial", item.dig("variants", "initial") || item ], [ "follow_up", item["follow_up"] ], [ "delayed_variant", item["delayed_variant"] ] ].each do |variant, body|
      next unless body.is_a?(Hash) && body["prompt"].present? && body["best_answer"].present?
      interview_count += 1
      actual = cards.find { |card| card[:id] == "arcade-#{item.fetch('id')}-#{variant}" }
      unless actual && actual[:answer] == body.fetch("best_answer") && actual[:prompt] == body.fetch("prompt") && actual[:options] == body.fetch("distractors", [])
        errors << "Interview content changed or missing: #{item.fetch('id')}/#{variant}"
      end
    end
  end
end
local_source = Content::FilesystemSource.new
source_differences = []
if Pathname(local_source.source_location).directory?
  stored = documents.index_by(&:source_path)
  local_source.documents.each do |entry|
    doc = stored[entry.fetch(:source_path)]
    source_differences << entry.fetch(:source_path) unless doc && doc.body_markdown == entry.fetch(:body_markdown)
  end
end
report = {
  documents: documents.size, represented_documents: by_document.size,
  cards: cards.size, library_cards: library_cards.size, arcade_questions_and_variants: interview_count,
  tracks: StudyCardCatalog::TRACKS.keys.to_h { |topic| [ topic, cards.count { |card| StudyCardCatalog.in_topic?(card, topic) } ] },
  imported_content_errors: errors, filesystem_differences: source_differences
}
puts JSON.pretty_generate(report)
abort "Catalog does not preserve the imported corpus" if errors.any?
