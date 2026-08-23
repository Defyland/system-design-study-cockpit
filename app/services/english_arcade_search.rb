require "json"

# Search facade for Arcade packs and the linked system-design-estudos corpus.
# It intentionally operates on the importer index in Ruby so the same search
# contract works before and after the optional Arcade tables are introduced.
class EnglishArcadeSearch
  SearchResult = Struct.new(
    :source_id,
    :target,
    :kind,
    :title,
    :source_path,
    :metadata,
    :score,
    :record,
    keyword_init: true
  ) do
    def to_h
      {
        "source_id" => source_id,
        "target" => target,
        "kind" => kind,
        "title" => title,
        "source_path" => source_path,
        "metadata" => metadata,
        "score" => score
      }
    end
  end

  attr_reader :query, :target, :kind

  def self.call(**options)
    new(**options).results
  end

  def initialize(
    q: nil,
    query: nil,
    target: nil,
    kind: nil,
    importer: nil,
    relation: nil,
    records: nil,
    include_study_documents: true
  )
    @query = (query.nil? ? q : query).to_s.strip
    @target = normalize_target(target)
    @kind = kind.to_s.strip.presence
    @importer = importer || Content::EnglishArcadeImporter.new
    @relation = relation
    @records = records
    @include_study_documents = include_study_documents
  end

  def results
    candidates = []
    candidates.concat(Array(@records || @importer.call).map { |record| from_importer_record(record) })
    candidates.concat(study_document_results) if @records.nil? && @include_study_documents

    tokens = search_tokens
    filtered = candidates.filter_map do |candidate|
      next if @target.present? && candidate.target != @target
      next if @kind.present? && candidate.kind != @kind

      score = score_candidate(candidate, tokens)
      next if tokens.any? && score.zero?

      candidate.score = score
      candidate
    end

    dedupe(filtered).sort_by { |candidate| [ -candidate.score.to_i, candidate.kind.to_s, candidate.title.to_s.downcase, candidate.source_id.to_s ] }
  end

  alias search results

  private

  def from_importer_record(record)
    if record.respond_to?(:source_id)
      SearchResult.new(
        source_id: record.source_id,
        target: normalize_target(record.target),
        kind: record.kind.to_s,
        title: record.title.to_s,
        source_path: record.source_path.to_s,
        metadata: stringify(record.metadata),
        record: record
      )
    else
      value = record.respond_to?(:to_h) ? record.to_h : {}
      SearchResult.new(
        source_id: value["source_id"] || value[:source_id],
        target: normalize_target(value["target"] || value[:target]),
        kind: (value["kind"] || value[:kind]).to_s,
        title: (value["title"] || value[:title]).to_s,
        source_path: (value["source_path"] || value[:source_path]).to_s,
        metadata: stringify(value["metadata"] || value[:metadata]),
        record: record
      )
    end
  end

  def study_document_results
    relation = @relation || (defined?(StudyDocument) ? StudyDocument.all : [])
    Array(relation.respond_to?(:to_a) ? relation.to_a : relation).filter_map do |document|
      metadata = stringify(document.respond_to?(:metadata) ? document.metadata : {})
      arcade_metadata = metadata["english_arcade"].is_a?(Hash) ? metadata["english_arcade"] : {}
      source_path = document.source_path.to_s
      source_id = arcade_metadata["source_id"] || metadata["source_id"] || Content::EnglishArcadeImporter.source_id_for(source_path)
      SearchResult.new(
        source_id: source_id,
        target: normalize_target(arcade_metadata["target"] || metadata["target"] || target_for_document(document)),
        kind: document.kind.to_s,
        title: document.title.to_s,
        source_path: source_path,
        metadata: metadata.merge("english_arcade" => arcade_metadata),
        record: document
      )
    end
  end

  def target_for_document(document)
    return "system_design" if document.kind.to_s.in?(%w[chapter lab capstone review_card decision_contrast curriculum])

    nil
  end

  def search_tokens
    query.to_s.downcase.split(/[\s,]+/).map(&:strip).reject(&:empty?)
  end

  def score_candidate(candidate, tokens)
    return 1 if tokens.empty?

    haystack = searchable_text(candidate)
    tokens.sum do |token|
      next 0 unless haystack.include?(token)

      score = 5
      score += 12 if candidate.title.to_s.downcase.include?(token)
      score += 10 if candidate.source_id.to_s.downcase == token
      score += 8 if candidate.source_path.to_s.downcase.include?(token)
      score
    end
  end

  def searchable_text(candidate)
    values = [ candidate.source_id, candidate.target, candidate.kind, candidate.title, candidate.source_path, candidate.metadata ]
    if candidate.record.respond_to?(:body_markdown)
      values << candidate.record.body_markdown
    elsif candidate.record.respond_to?(:search_text)
      values << candidate.record.search_text
    end
    flatten(values).join(" ").downcase
  end

  def flatten(value)
    case value
    when Hash
      value.flat_map { |key, entry| flatten([ key, entry ]) }
    when Array
      value.flat_map { |entry| flatten(entry) }
    else
      [ value ].compact.map(&:to_s)
    end
  end

  def dedupe(candidates)
    candidates.each_with_object({}) do |candidate, unique|
      key = candidate.source_id.presence || "#{candidate.kind}:#{candidate.source_path}"
      existing = unique[key]
      unique[key] = candidate if existing.nil? || candidate.score.to_i > existing.score.to_i
    end.values
  end

  def stringify(value)
    return {} if value.nil?

    value.respond_to?(:to_h) ? value.to_h.transform_keys(&:to_s) : value
  end

  def normalize_target(value)
    normalized = value.to_s.strip.downcase.tr("-", "_")
    normalized = "system_design" if normalized == "systemdesign"
    normalized.presence
  end
end
