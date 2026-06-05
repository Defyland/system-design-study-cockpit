class CurriculumGraph
  CACHE_KEY = "study_content/curriculum"

  def self.current(cache: Rails.cache)
    new(cache.read(CACHE_KEY) || {})
  rescue ActiveRecord::StatementInvalid, ArgumentError
    new({})
  end

  def initialize(curriculum)
    @curriculum = curriculum.presence || {}
    @areas_by_id = Array(@curriculum["areas"]).index_by { |area| area.fetch("id") }
    @phase_titles_by_id = Array(@curriculum["phases"]).to_h do |phase|
      phase_id = phase.fetch("id")
      [ phase_id, phase.fetch("title", phase_id) ]
    end
    @chapters = Array(@curriculum["chapters"]).sort_by { |chapter| chapter.fetch("number").to_i }
    @chapters_by_slug = @chapters.index_by { |chapter| chapter.fetch("slug") }
    @chapters_by_path = @chapters.index_by { |chapter| chapter.fetch("path") }
    @chapters_by_lab_path = @chapters.index_by { |chapter| chapter.dig("lab", "path") }.compact
    @chapters_by_review_path = @chapters.index_by { |chapter| chapter.dig("review_card", "path") }.compact
  end

  def chapters
    @chapters
  end

  def total_chapters
    @chapters.size
  end

  def area(area_id)
    @areas_by_id[area_id]
  end

  def phase_title(phase_id)
    @phase_titles_by_id[phase_id] || phase_id
  end

  def chapter_for_document(document)
    return unless document

    chapter_for(kind: document.kind, source_path: document.source_path, slug: document.slug)
  end

  def metadata_for(kind:, source_path:, slug:)
    chapter = chapter_for(kind: kind, source_path: source_path, slug: slug)

    case kind
    when "chapter"
      chapter ? chapter_metadata(chapter) : {}
    when "lab", "review_card"
      chapter ? child_metadata(chapter, kind) : {}
    when "real_world_case"
      real_world_case_metadata(source_path)
    when "decision_contrast"
      decision_contrast_metadata(source_path)
    when "simulation_lab"
      simulation_lab_metadata(slug || File.basename(source_path.to_s, ".md"))
    else
      {}
    end
  end

  private

  def chapter_for(kind:, source_path:, slug:)
    case kind
    when "chapter"
      @chapters_by_path[source_path] || @chapters_by_slug[slug]
    when "lab"
      @chapters_by_lab_path[source_path]
    when "review_card"
      @chapters_by_review_path[source_path]
    end
  end

  def chapter_metadata(chapter)
    {
      "curriculum_id" => chapter.fetch("id"),
      "chapter_number" => chapter.fetch("number"),
      "chapter_slug" => chapter.fetch("slug"),
      "study_order" => "#{chapter.fetch("number")}/#{total_chapters}",
      "phase_id" => chapter.fetch("phase"),
      "phase_title" => phase_title(chapter.fetch("phase")),
      "primary_area_id" => chapter.fetch("primary_area"),
      "primary_area_title" => area_title(chapter.fetch("primary_area")),
      "secondary_area_ids" => Array(chapter["secondary_areas"]),
      "secondary_area_titles" => Array(chapter["secondary_areas"]).map { |area_id| area_title(area_id) },
      "notes_paths" => Array(chapter["notes"]),
      "primary_case_id" => chapter.dig("primary_case", "id"),
      "primary_case_title" => chapter.dig("primary_case", "title"),
      "primary_case_path" => chapter.dig("primary_case", "path"),
      "complementary_cases" => Array(chapter["complementary_cases"]),
      "lab_path" => chapter.dig("lab", "path"),
      "review_card_path" => chapter.dig("review_card", "path"),
      "suggested_contrast_id" => chapter.dig("suggested_contrast", "id"),
      "suggested_contrast_title" => chapter.dig("suggested_contrast", "title"),
      "suggested_contrast_path" => chapter.dig("suggested_contrast", "path"),
      "simulations" => Array(chapter["simulations"]),
      "estimated_minutes" => chapter["estimated_minutes"],
      "mastery_objectives" => Array(chapter["mastery_objectives"]),
      "interview_objectives" => Array(chapter["interview_objectives"])
    }.compact
  end

  def child_metadata(chapter, kind)
    label = kind == "lab" ? "lab_path" : "review_card_path"

    {
      "curriculum_id" => chapter.fetch("id"),
      "chapter_number" => chapter.fetch("number"),
      "chapter_slug" => chapter.fetch("slug"),
      "chapter_title" => chapter.fetch("title"),
      "phase_id" => chapter.fetch("phase"),
      "phase_title" => phase_title(chapter.fetch("phase")),
      label => kind == "lab" ? chapter.dig("lab", "path") : chapter.dig("review_card", "path")
    }.compact
  end

  def real_world_case_metadata(source_path)
    used_by = @chapters.filter_map do |chapter|
      role = case_role(chapter, source_path)
      next unless role

      chapter_ref(chapter).merge("role" => role)
    end

    return {} if used_by.blank?

    { "used_by_chapters" => used_by }
  end

  def decision_contrast_metadata(source_path)
    used_by = @chapters.filter_map do |chapter|
      next unless chapter.dig("suggested_contrast", "path") == source_path

      chapter_ref(chapter)
    end

    return {} if used_by.blank?

    { "used_by_chapters" => used_by }
  end

  def simulation_lab_metadata(slug)
    used_by = @chapters.filter_map do |chapter|
      next unless Array(chapter["simulations"]).include?(slug)

      chapter_ref(chapter)
    end

    return {} if used_by.blank?

    { "used_by_chapters" => used_by }
  end

  def case_role(chapter, source_path)
    return "primary" if chapter.dig("primary_case", "path") == source_path

    Array(chapter["complementary_cases"]).any? { |use_case| use_case["path"] == source_path } ? "complementary" : nil
  end

  def chapter_ref(chapter)
    {
      "number" => chapter.fetch("number"),
      "slug" => chapter.fetch("slug"),
      "title" => chapter.fetch("title"),
      "path" => chapter.fetch("path")
    }
  end

  def area_title(area_id)
    @areas_by_id.dig(area_id, "title") || area_id
  end
end
