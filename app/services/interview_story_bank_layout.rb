class InterviewStoryBankLayout
  QA_SECTION_HEADING = /^##\s+Q&A de Reserva.*$/i
  QUESTION_HEADING = /^###\s+(.+?)\n+(.+?)(?=^###\s+|\z)/m
  QUESTION_AREAS = [
    [ "resume", "Meu curriculo" ],
    [ "ruby", "Ruby" ],
    [ "rails", "Ruby on Rails" ],
    [ "performance", "Performance" ]
  ].freeze
  DEFAULT_AREA_KEY = "rails"
  AREA_MATCHERS = [
    [ "resume", /\b(curr[ií]culo|trajet[oó]ria|experi[eê]ncia|carreira|projeto|produto|time|lideran[cç]a|2016|2017|2018|2019|2020|2021|2022|2023|2024|2025|2026)\b/i ],
    [ "performance", /\b(performance|throughput|lat[eê]ncia|cache|deadlock|lock|isolamento|[ií]ndice|index|sql|query|n\+1|puma|thread|fila|job|deploy|consist[eê]ncia|transa[cç][aã]o|concorr[eê]ncia|escala|alto volume|milh[oõ]es|timeout|mem[oó]ria)\b/i ],
    [ "rails", /\b(rails|ruby on rails|active ?record|migration|controller|callback|validation|zeitwerk|autoload|action ?cable|active ?job|solid queue|turbo|stimulus)\b/i ],
    [ "ruby", /\b(ruby|gvl|gil|ractor|fiber|enumerable|metaprograma[cç][aã]o|object model|block|proc|lambda|gem|bundler|garbage collector|symbol)\b/i ]
  ].freeze

  Question = Struct.new(:index, :anchor, :prompt, :answer_markdown, :area_key, keyword_init: true)
  QuestionGroup = Struct.new(:key, :label, :questions, keyword_init: true)

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
      prompt_text = question_prompt(prompt, answer)

      Question.new(
        index: index + 1,
        anchor: "story-bank-question-#{index + 1}",
        prompt: prompt_text,
        answer_markdown: answer_without_prompt(answer),
        area_key: question_area_for(prompt_text, answer)
      )
    end
  end

  def question_groups
    @question_groups ||= QUESTION_AREAS.map do |key, label|
      QuestionGroup.new(
        key: key,
        label: label,
        questions: questions.select { |question| question.area_key == key }
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

  def question_area_for(prompt, answer_markdown)
    text = "#{prompt} #{answer_markdown}"
    AREA_MATCHERS.each do |key, matcher|
      return key if text.match?(matcher)
    end

    DEFAULT_AREA_KEY
  end

  def normalized_markdown(markdown)
    markdown.to_s.gsub(/\r\n?/, "\n").gsub(/\n{3,}/, "\n\n").strip
  end
end
