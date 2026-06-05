require "digest"

module Content
  class MarkdownParser
    PARSER_VERSION = 4
    CHECKPOINT_HEADING = /\A\#{2,4}\s+.*(Fixacao|Recall|First Pass|Production Recall|Design Pass Recall)/i
    LABELLED_BULLET = /\A-\s+`([^`]+)`:\s*(.+)\z/

    def parse(kind:, source_path:, body_markdown:)
      {
        kind: kind,
        slug: slug_for(source_path),
        title: title_for(body_markdown, source_path),
        source_path: source_path,
        phase: phase_for(body_markdown),
        position: position_for(source_path),
        body_markdown: body_markdown,
        body_checksum: Digest::SHA256.hexdigest("#{PARSER_VERSION}\n#{body_markdown}"),
        metadata: metadata_for(body_markdown),
        blocks: blocks_for(body_markdown),
        checkpoints: checkpoints_for(body_markdown)
      }
    end

    private

    def slug_for(source_path)
      return File.basename(File.dirname(source_path)) if File.basename(source_path) == "README.md"

      File.basename(source_path, ".md")
    end

    def title_for(body_markdown, source_path)
      body_markdown.each_line do |line|
        return line.delete_prefix("#").strip if line.start_with?("# ")
      end

      slug_for(source_path).tr("-", " ").titleize
    end

    def phase_for(body_markdown)
      body_markdown[/`Study Order`:\s*`\d+\/14`\s*-\s*`([^`]+)`/, 1]
    end

    def position_for(source_path)
      File.basename(source_path)[/\A(?:chapter-)?(\d{2})/, 1].to_i
    end

    def metadata_for(body_markdown)
      {
        "study_order" => body_markdown[/`Study Order`:\s*`([^`]+)`/, 1],
        "primary_case" => body_markdown[/`Caso real principal`:\s*\[([^\]]+)\]/, 1],
        "primary_area" => body_markdown[/`Area principal`:\s*\[([^\]]+)\]/, 1]
      }.compact
    end

    def blocks_for(body_markdown)
      visible_markdown(body_markdown)
        .split(/\n{2,}/)
        .map(&:strip)
        .reject(&:blank?)
        .each_with_index
        .map do |content, index|
          {
            position: index + 1,
            kind: block_kind(content),
            content_markdown: content
          }
        end
    end

    def visible_markdown(body_markdown)
      sections_for(body_markdown)
        .reject { |section| section[:heading].match?(CHECKPOINT_HEADING) }
        .map { |section| section_markdown(section) }
        .join("\n")
    end

    def section_markdown(section)
      lines = []
      lines << section[:heading] unless section[:heading] == "Document"
      lines.concat(section[:body])
      lines.join
    end

    def block_kind(content)
      return "heading" if content.start_with?("#")
      return "code" if content.start_with?("```")
      return "list" if content.start_with?("- ", "1. ")

      "paragraph"
    end

    def checkpoints_for(body_markdown)
      sections_for(body_markdown).each_with_index.filter_map do |section, index|
        next unless section[:heading].match?(CHECKPOINT_HEADING)

        checkpoint_from(section, index + 1)
      end
    end

    def sections_for(body_markdown)
      sections = []
      current = { heading: "Document", body: [] }

      body_markdown.each_line do |line|
        if line.match?(/\A\#{2,4}\s+/)
          sections << current
          current = { heading: line.strip, body: [] }
        else
          current[:body] << line
        end
      end

      sections << current
      sections
    end

    def checkpoint_from(section, position)
      labels = labelled_bullets(section[:body])
      plain = section[:body].join.strip

      return if labels.blank? && plain.blank?

      prompt = labels["Pergunta"] || labels["Requirement"] || labels["Requirement Less Dumb"] || plain.lines.first&.strip
      good_answer = labels["Resposta com as suas palavras"] ||
        labels["Resposta curta"] ||
        labels["Forma mais simples"] ||
        labels["Simplify"] ||
        labels.values.first ||
        "Explique em voz alta antes de revelar."

      {
        position: position,
        source_label: section[:heading].sub(/\A#+\s*/, "").strip,
        prompt: prompt,
        good_answer: good_answer,
        bad_answer: labels["Resposta ruim que parece boa"] || labels["Resposta ruim"] || labels["Armadilha"],
        correction: labels["Troque por isto"] || labels["Correcao"] || labels["Correção"]
      }
    end

    def labelled_bullets(lines)
      lines.each_with_object({}) do |line, labels|
        match = line.strip.match(LABELLED_BULLET)
        next unless match

        labels[match[1]] = match[2]
      end
    end
  end
end
