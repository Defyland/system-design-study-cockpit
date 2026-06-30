class StudySearch
  QuickFilter = Struct.new(:key, :label, keyword_init: true)

  QUICK_FILTERS = [
    QuickFilter.new(key: "dsa", label: "DSA"),
    QuickFilter.new(key: "rails", label: "Rails"),
    QuickFilter.new(key: "system_design", label: "System Design"),
    QuickFilter.new(key: "snippets", label: "Snippets"),
    QuickFilter.new(key: "reference_docs", label: "Reference Docs")
  ].freeze

  def self.quick_filters
    QUICK_FILTERS
  end

  def initialize(q: nil, kind: nil, quick_filter: nil, relation: StudyDocument.all)
    @q = q.to_s.strip
    @kind = kind.to_s.presence
    @quick_filter = quick_filter.to_s.presence
    @relation = relation
  end

  def results
    scope = @relation
    scope = scope.where(kind: @kind) if @kind.present?
    scope = apply_quick_filter(scope)
    scope = apply_query(scope)
    scope.order(:kind, :position, :title)
  end

  private

  def apply_query(scope)
    return scope if @q.blank?

    pattern = "%#{@q.downcase}%"
    scope.where(
      "LOWER(title) LIKE :pattern OR LOWER(source_path) LIKE :pattern OR LOWER(body_markdown) LIKE :pattern",
      pattern: pattern
    )
  end

  def apply_quick_filter(scope)
    case @quick_filter
    when "dsa"
      keyword_scope(scope, %w[
        dsa algorithm algorithms two\ sum sliding\ window binary\ search dfs bfs dynamic\ programming
        hash\ map heap interval palindrome graph tree
      ])
    when "rails"
      keyword_scope(scope, %w[
        rails ruby active\ record postgres sidekiq cache transaction idempotent authz n+1
      ])
    when "system_design"
      keyword_scope(scope, %w[
        system\ design rate\ limit cache sharding partition feed chat notification load\ balancer queue
        idempotency consistency architecture
      ])
    when "snippets"
      scope.where("source_path LIKE ?", "%/snippets/%")
    when "reference_docs"
      scope.where(kind: "reference_document")
    else
      scope
    end
  end

  def keyword_scope(scope, keywords)
    clauses = keywords.each_with_index.map do |_keyword, index|
      "LOWER(title) LIKE :pattern_#{index} OR LOWER(source_path) LIKE :pattern_#{index} OR LOWER(body_markdown) LIKE :pattern_#{index}"
    end

    bindings = keywords.each_with_index.to_h do |keyword, index|
      [ :"pattern_#{index}", "%#{keyword.downcase}%" ]
    end

    scope.where(clauses.join(" OR "), bindings)
  end
end
