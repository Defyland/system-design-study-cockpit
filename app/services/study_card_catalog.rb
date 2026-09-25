class StudyCardCatalog
  TOPICS = { "all" => "Todos os assuntos", "frontend" => "Frontend", "backend" => "Backend", "system" => "System design", "algorithms" => "Algoritmos", "english" => "Inglês", "fullstack" => "Full-stack", "smarttv" => "Smart TV" }.freeze
  TRACKS = {
    "ruby" => "Ruby", "rails" => "Ruby on Rails", "golang" => "Golang", "elixir" => "Elixir",
    "react" => "React", "dsa" => "DSA", "databases" => "Bancos de dados",
    "general" => "Inglês profissional", "career" => "Carreira e entrevistas",
    "rails_experience" => "Experiência Rails", "go_experience" => "Experiência Go",
    "elixir_experience" => "Experiência Elixir", "system_design" => "System design · entrevistas",
    "salesforce" => "Salesforce", "library" => "Biblioteca completa"
  }.freeze
  RIPPLING = "https://medium.com/frontend-army/rippling-frontend-interview-experience-senior-software-engineer-f0c86ec2c4fd".freeze

  def cards
    @cards ||= authored + resume_cards + arcade_cards + StudyDocumentCards.new.cards
  end

  def topics
    TOPICS.slice("all").merge(TRACKS).merge(TOPICS.except("all"))
      .merge(ContentKind.entries.to_h { |entry| [ "kind:#{entry.key}", "Acervo · #{entry.label}" ] })
      .merge(StudyDocument.side_track_overview.pluck(:slug, :title).to_h { |slug, title| [ "track:#{slug}", title ] })
  end

  def self.in_topic?(card, topic)
    topic == "all" || Array(card[:topics] || card.fetch(:topic)).include?(topic)
  end

  private

  def arcade_content
    @arcade_content ||= ArcadeContent.new
  end

  def arcade_cards
    content = arcade_content
    content.targets.flat_map do |target|
      content.items_for(target).flat_map do |item|
        [ [ "initial", item.dig("variants", "initial") || item ], [ "follow_up", item["follow_up"] ], [ "delayed_variant", item["delayed_variant"] ] ].filter_map do |variant, body|
          next unless body.is_a?(Hash) && body["prompt"].present? && body["best_answer"].present?

          {
            id: "arcade-#{item.fetch('id')}-#{variant}", topic: target,
            topics: [ target, *({ "rails_experience" => [ "rails" ], "go_experience" => [ "golang" ], "elixir_experience" => [ "elixir" ] }[target] || []) ],
            prompt: body.fetch("prompt"), answer: body.fetch("best_answer"),
            context: body["context"] || item["context"], options: body["distractors"] || [],
            coaching: body.slice("feedback", "critical_thinking", "check").merge(
              variant == "initial" ? item.slice("rephrase_prompt", "extension_prompt", "compression_prompt", "feynman", "black_box", "recall", "sources").merge("answer_versions" => item["_response_versions"]) : {}
            ),
            source: "English Arcade · #{TRACKS.fetch(target)} · #{variant == 'initial' ? 'pergunta original' : 'variação autorada'}",
            source_url: nil
          }
        end
      end
    end
  end

  def resume_cards
    arcade_content.items_for("interview").flat_map do |item|
      [ [ "initial", item ], [ "follow_up", item.fetch("follow_up") ], [ "delayed_variant", item.fetch("delayed_variant") ] ].map do |variant, body|
        reasoning = item.fetch("learning").fetch("reasoning_questions")
        {
          id: "#{item.fetch('id')}-#{variant}", topic: item.fetch("interview_role"),
          prompt: body.fetch("prompt"), answer: body.fetch("best_answer"),
          reasoning: variant == "initial" ? reasoning.first.fetch("answer") : "Eu identifico a condição que mudou nesta pergunta e separo os fatos do meu currículo da decisão que eu tomaria nesse cenário.",
          alternative: reasoning[2].fetch("answer"),
          trap: body.fetch("distractors").first.fetch("text"),
          explanation: body.fetch("distractors").first.fetch("why_wrong"),
          source: "#{variant == 'initial' ? 'Ensaio' : 'Variação para treino'} · currículo já documentado no cockpit",
          source_url: nil
        }
      end
    end
  end

  def authored
    YAML.safe_load_file(Rails.root.join("config/study_cards.yml")).map do |card|
      card.symbolize_keys.merge(source_url: card["reported"] ? RIPPLING : nil,
        source: card["reported"] ? "Adaptada do relato · Rippling / Gourav Hammad · resposta didática" : "Simulação autoral · variação para treino")
    end
  end
end
