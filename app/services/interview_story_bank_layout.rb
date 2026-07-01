class InterviewStoryBankLayout
  QA_SECTION_HEADING = /^##\s+Q&A de Reserva.*$/i
  QUESTION_HEADING = /^###\s+(.+?)\n+(.+?)(?=^###\s+|\z)/m

  Question = Struct.new(:index, :anchor, :prompt, :answer_markdown, keyword_init: true)

  def initialize(document:)
    @document = document
  end

  def available?
    questions.any?
  end

  def narrative_markdown
    @narrative_markdown ||= normalized_markdown(strip_title(split_sections.fetch(:narrative)))
  end

  def qa_intro_markdown
    @qa_intro_markdown ||= normalized_markdown(split_sections.fetch(:qa_intro))
  end

  def questions
    @questions ||= split_sections.fetch(:qa_source).scan(QUESTION_HEADING).each_with_index.map do |(prompt, answer_markdown), index|
      answer = normalized_markdown(answer_markdown)

      Question.new(
        index: index + 1,
        anchor: "story-bank-question-#{index + 1}",
        prompt: question_prompt(prompt, answer),
        answer_markdown: answer_without_prompt(answer)
      )
    end
  end

  private

  def split_sections
    @split_sections ||= begin
      narrative, qa_source = @document.body_markdown.to_s.split(QA_SECTION_HEADING, 2)
      qa_source = normalized_markdown(qa_source)
      qa_intro = qa_source.split(/^###\s+/, 2).first

      {
        narrative: narrative,
        qa_source: qa_source,
        qa_intro: qa_intro
      }
    end
  end

  def strip_title(markdown)
    markdown.to_s.sub(/\A#\s+.+?\n+/, "")
  end

  def question_prompt(heading, answer_markdown)
    answer_markdown[/\A\*\*Q:\s*(.+?)\*\*/, 1]&.strip || heading.strip
  end

  def answer_without_prompt(answer_markdown)
    answer_markdown.sub(/\A\*\*Q:\s*.+?\*\*\s*/m, "").strip
  end

  def normalized_markdown(markdown)
    markdown.to_s.gsub(/\r\n?/, "\n").gsub(/\n{3,}/, "\n\n").strip
  end
end
