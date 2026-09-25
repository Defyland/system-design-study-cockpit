require "digest"

class StudyQuizCatalog
  def initialize(cards: StudyCardCatalog.new.cards)
    @cards = cards.select do |card|
      card[:id].start_with?("arcade-") && card[:answer].present? &&
        Array(card[:options]).length >= 2 && Array(card[:options]).all? { |option| option["text"].present? && option["why_wrong"].present? }
    end
    @document_ids_by_path = StudyDocument.pluck(:source_path, :id).to_h
  end

  def cards
    @cards
  end

  def find(key)
    @cards.find { |card| card[:id] == key }
  end

  def source_document_ids(card)
    Array(card.dig(:coaching, "sources")).filter_map { |source| @document_ids_by_path[source["path"]] }.uniq
  end

  def choices(card)
    ([ { "text" => card.fetch(:answer), "why_wrong" => nil } ] + card.fetch(:options)).each_with_index.map do |option, index|
      option.merge("id" => Digest::SHA256.hexdigest("#{card.fetch(:id)}:#{index}")[0, 12], "correct" => index.zero?)
    end.sort_by { |option| Digest::SHA256.hexdigest("#{card.fetch(:id)}:order:#{option.fetch('id')}") }
  end
end
