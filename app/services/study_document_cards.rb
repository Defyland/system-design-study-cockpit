# Read the complete imported library without rewriting its authored answers.
class StudyDocumentCards
  TECH_TRACKS = {
    "ruby" => /\bruby\b/i,
    "rails" => /\brails\b|active\s*record|sidekiq/i,
    "golang" => /\bgolang\b|\bGo\b|goroutine/i,
    "elixir" => /\belixir\b|\bphoenix\b|\bOTP\b|\bBEAM\b/i,
    "react" => /\breact\b|\bjsx\b/i,
    "databases" => /postgres|mysql|\bsql\b|database|banco de dados/i
  }.freeze

  def initialize(documents: StudyDocument.ordered)
    @documents = documents
  end

  def cards
    @documents.flat_map do |document|
      occurrences = Hash.new(0)
      sections(document.body_markdown).map do |section|
        heading = section[/^\#{1,3}\s+(.+)$/, 1] || document.title
        occurrences[heading] += 1
        id = Digest::SHA256.hexdigest("#{document.source_path}\n#{heading}\n#{occurrences[heading]}")[0, 24]
        topics = [ "library", "kind:#{document.kind}" ]
        topics << "track:#{document.side_track_id}" if document.side_track_id.present?
        TECH_TRACKS.each { |key, pattern| topics << key if "#{document.title}\n#{heading}".match?(pattern) }
        {
          id: "library-#{id}", topic: topics.last, topics: topics,
          prompt: section[/^\*\*Q:\s*(.+?)\*\*/, 1] || heading, answer_markdown: section,
          document_title: document.title, document_id: document.id, source_path: document.source_path,
          source: "Acervo · #{ContentKind.entries.find { |entry| entry.key == document.kind }&.label || document.kind}",
          source_url: Rails.application.routes.url_helpers.study_card_source_path(document.id)
        }
      end
    end
  end

  # Keep fenced code, tables, authored Q&A and all text intact. Headings inside
  # fences are code, not boundaries. IDs depend on source + heading, not DB IDs.
  def sections(markdown)
    result = []
    current = +""
    fence = nil
    markdown.each_line do |line|
      marker = line.match(/^\s{0,3}(`{3,}|~{3,})/)&.[](1)
      if marker
        if fence.nil?
          fence = marker
        elsif marker[0] == fence[0] && marker.length >= fence.length && line.strip == marker
          fence = nil
        end
      elsif fence.nil? && line.match?(/^\#{1,3}\s+/) && current.present?
        result << current
        current = +""
      end
      current << line
    end
    result << current if current.present?
    compact = []
    pending = +""
    result.each do |section|
      pending << section
      next if pending.gsub(/^\#{1,6}[^\n]*/, "").strip.empty?

      compact << pending
      pending = +""
    end
    if pending.present?
      compact.empty? ? compact << pending : compact[-1] << pending
    end
    compact
  end
end
