module ApplicationHelper
  def study_context_link(link)
    return "Nao catalogado" unless link

    if link.document
      link_to link.title, library_document_path(kind: link.document.kind, slug: link.document.slug)
    else
      content_tag(:span, link.title, title: link.source_path)
    end
  end

  def study_context_links(links)
    safe_join(links.compact.map { |link| study_context_link(link) }, tag.br)
  end
end
