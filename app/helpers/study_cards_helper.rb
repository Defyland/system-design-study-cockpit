module StudyCardsHelper
  def study_card_markdown(markdown, source_path: nil)
    html = Nokogiri::HTML.fragment(render_markdown(markdown))
    if source_path
      @study_source_links ||= StudyDocument.pluck(:source_path, :id).to_h
      html.css("a[href]").each do |link|
        href = link["href"]
        next if href.match?(%r{\A(?:[a-z]+:|//|#)}i)

        path = Pathname.new(File.dirname(source_path)).join(href.split("#").first).cleanpath.to_s
        document_id = @study_source_links[path]
        if document_id
          link["href"] = study_card_source_path(document_id)
        else
          # Keep unavailable corpus references as text, not broken app URLs.
          link.replace(Nokogiri::XML::Text.new(link.text, html.document))
        end
      end
    end
    html.to_html.html_safe
  end

  def study_coaching(value)
    case value
    when Hash
      safe_join(value.filter_map do |key, nested|
        next if nested.blank?
        tag.div(safe_join([ tag.strong(key.to_s.humanize), study_coaching(nested) ]), class: "study-coaching")
      end)
    when Array
      tag.ul(safe_join(value.map { |entry| tag.li(study_coaching(entry)) }))
    else
      tag.p(value.to_s)
    end
  end
end
