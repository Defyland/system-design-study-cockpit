module MarkdownHelper
  def render_markdown(markdown)
    sanitize(
      Commonmarker.to_html(markdown.to_s),
      tags: %w[
        a blockquote code em h1 h2 h3 h4 hr li ol p pre strong table tbody td th thead tr ul
      ],
      attributes: %w[href title]
    )
  end
end
