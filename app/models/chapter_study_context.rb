class ChapterStudyContext
  Link = Struct.new(:title, :source_path, :document, keyword_init: true)

  def initialize(chapter, graph: CurriculumGraph.current)
    @chapter = chapter
    @graph = graph
    @entry = graph.chapter_for_document(chapter) || entry_from_metadata
  end

  def available?
    @entry.present?
  end

  def study_order
    return @chapter.metadata["study_order"] if @chapter.metadata["study_order"].present?

    "#{@entry.fetch("number")}/#{@graph.total_chapters}"
  end

  def phase_title
    return @entry["phase_title"] if @entry["phase_title"].present?

    @graph.phase_title(@entry.fetch("phase"))
  end

  def primary_area
    @primary_area ||= area_link(@entry.fetch("primary_area"))
  end

  def secondary_areas
    @secondary_areas ||= Array(@entry["secondary_areas"]).map { |area_id| area_link(area_id) }
  end

  def notes
    @notes ||= Array(@entry["notes"]).map do |path|
      Link.new(title: path, source_path: path)
    end
  end

  def primary_case
    @primary_case ||= case_link(@entry["primary_case"])
  end

  def complementary_cases
    @complementary_cases ||= Array(@entry["complementary_cases"]).map { |use_case| case_link(use_case) }
  end

  def lab
    @lab ||= document_link(kind: "lab", source_path: @entry.dig("lab", "path"), title: "Lab do chapter")
  end

  def review_card
    @review_card ||= document_link(kind: "review_card", source_path: @entry.dig("review_card", "path"), title: "Review card")
  end

  def suggested_contrast
    return @suggested_contrast if defined?(@suggested_contrast)

    contrast = @entry["suggested_contrast"]
    @suggested_contrast = document_link(kind: "decision_contrast", source_path: contrast&.fetch("path", nil), title: contrast&.fetch("title", nil))
  end

  def simulations
    @simulations ||= Array(@entry["simulations"]).map do |slug|
      document = StudyDocument.find_by(kind: "simulation_lab", slug: slug)
      Link.new(title: slug.tr("-", " ").titleize, source_path: "simulation-labs/#{slug}.md", document: document)
    end
  end

  def mastery_objectives
    Array(@entry["mastery_objectives"])
  end

  def interview_objectives
    Array(@entry["interview_objectives"])
  end

  private

  def area_link(area_id)
    area = @graph.area(area_id)
    title = area ? area.fetch("title") : area_title_from_metadata(area_id)
    source_path = area&.dig("content_dirs", "notes")

    Link.new(title: title, source_path: source_path)
  end

  def case_link(use_case)
    return unless use_case

    document_link(kind: "real_world_case", source_path: use_case.fetch("path"), title: use_case.fetch("title"))
  end

  def document_link(kind:, source_path:, title:)
    return unless source_path.present? && title.present?

    document = StudyDocument.find_by(kind: kind, source_path: source_path)
    Link.new(title: title, source_path: source_path, document: document)
  end

  def entry_from_metadata
    metadata = @chapter.metadata
    return if metadata["curriculum_id"].blank?

    {
      "id" => metadata["curriculum_id"],
      "number" => metadata["chapter_number"],
      "title" => @chapter.title,
      "slug" => metadata["chapter_slug"] || @chapter.slug,
      "path" => @chapter.source_path,
      "phase" => metadata["phase_id"],
      "phase_title" => metadata["phase_title"],
      "primary_area" => metadata["primary_area_id"],
      "secondary_areas" => Array(metadata["secondary_area_ids"]),
      "notes" => Array(metadata["notes_paths"]),
      "primary_case" => {
        "id" => metadata["primary_case_id"],
        "title" => metadata["primary_case_title"],
        "path" => metadata["primary_case_path"]
      }.compact,
      "complementary_cases" => Array(metadata["complementary_cases"]),
      "lab" => { "path" => metadata["lab_path"] }.compact,
      "review_card" => { "path" => metadata["review_card_path"] }.compact,
      "suggested_contrast" => {
        "id" => metadata["suggested_contrast_id"],
        "title" => metadata["suggested_contrast_title"],
        "path" => metadata["suggested_contrast_path"]
      }.compact,
      "simulations" => Array(metadata["simulations"]),
      "mastery_objectives" => Array(metadata["mastery_objectives"]),
      "interview_objectives" => Array(metadata["interview_objectives"])
    }
  end

  def area_title_from_metadata(area_id)
    metadata = @chapter.metadata
    return metadata["primary_area_title"] if area_id == metadata["primary_area_id"]

    secondary_ids = Array(metadata["secondary_area_ids"])
    secondary_titles = Array(metadata["secondary_area_titles"])
    secondary_titles[secondary_ids.index(area_id)] || area_id
  end
end
