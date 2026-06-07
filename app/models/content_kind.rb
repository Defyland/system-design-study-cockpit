class ContentKind
  Entry = Struct.new(
    :key,
    :label,
    :short_label,
    :library,
    :navigation,
    :dashboard,
    :filesystem_pattern,
    :github_directory,
    :github_pattern,
    :github_recursive,
    keyword_init: true
  )

  ENTRIES = [
    Entry.new(
      key: "chapter",
      label: "Chapters",
      filesystem_pattern: "chapters/chapter-*.md",
      github_directory: "chapters",
      github_pattern: /\Achapter-.*\.md\z/
    ),
    Entry.new(
      key: "lab",
      label: "Labs",
      library: true,
      filesystem_pattern: "labs/chapters/chapter-*.md",
      github_directory: "labs/chapters",
      github_pattern: /\Achapter-.*\.md\z/
    ),
    Entry.new(
      key: "review_card",
      label: "Review Cards",
      library: true,
      filesystem_pattern: "reviews/cards/*.md",
      github_directory: "reviews/cards",
      github_pattern: /\A\d{2}-.*\.md\z/
    ),
    Entry.new(
      key: "capstone",
      label: "Capstones",
      filesystem_pattern: "capstones/[0-9][0-9]-*.md",
      github_directory: "capstones",
      github_pattern: /\A\d{2}-.*\.md\z/
    ),
    Entry.new(
      key: "foundation",
      label: "Foundations",
      short_label: "Fundamentos",
      library: true,
      navigation: true,
      dashboard: true,
      filesystem_pattern: "areas/06-foundations-distribuidas/topics/*.md",
      github_directory: "areas/06-foundations-distribuidas/topics",
      github_pattern: /\A.+\.md\z/
    ),
    Entry.new(
      key: "component_card",
      label: "Componentes",
      short_label: "Componentes",
      library: true,
      navigation: true,
      dashboard: true,
      filesystem_pattern: "areas/07-componentes-de-sistemas/cards/*.md",
      github_directory: "areas/07-componentes-de-sistemas/cards",
      github_pattern: /\A.+\.md\z/
    ),
    Entry.new(
      key: "simulation_lab",
      label: "Simulation Labs",
      library: true,
      filesystem_pattern: "simulation-labs/*.md",
      github_directory: "simulation-labs",
      github_pattern: /\A(?!README\.md).+\.md\z/
    ),
    Entry.new(
      key: "ai_system",
      label: "Sistemas de IA",
      short_label: "IA",
      library: true,
      navigation: true,
      dashboard: true,
      filesystem_pattern: "areas/08-sistemas-ia/topics/*.md",
      github_directory: "areas/08-sistemas-ia/topics",
      github_pattern: /\A.+\.md\z/
    ),
    Entry.new(
      key: "backend_principle",
      label: "Backend Principles",
      short_label: "Backend",
      library: true,
      navigation: true,
      dashboard: true,
      filesystem_pattern: "areas/09-backend-principles/cards/*.md",
      github_directory: "areas/09-backend-principles/cards",
      github_pattern: /\A.+\.md\z/
    ),
    Entry.new(
      key: "engineering_case_study",
      label: "Engineering Case Studies",
      short_label: "Engineering",
      library: true,
      navigation: true,
      dashboard: true,
      filesystem_pattern: "areas/10-engineering-case-studies/cards/*.md",
      github_directory: "areas/10-engineering-case-studies/cards",
      github_pattern: /\A.+\.md\z/
    ),
    Entry.new(
      key: "real_world_case",
      label: "Casos reais",
      short_label: "Casos",
      library: true,
      navigation: true,
      dashboard: true,
      filesystem_pattern: "real-world-cases/**/README.md",
      github_directory: "real-world-cases",
      github_pattern: %r{/README\.md\z},
      github_recursive: true
    ),
    Entry.new(
      key: "decision_contrast",
      label: "Contrastes",
      library: true,
      filesystem_pattern: "decision-contrasts/[0-9][0-9]-*.md",
      github_directory: "decision-contrasts",
      github_pattern: /\A\d{2}-.*\.md\z/
    )
  ].freeze

  def self.enum_mapping
    entries.to_h { |entry| [ entry.key.to_sym, entry.key ] }
  end

  def self.filesystem_patterns
    entries.select(&:filesystem_pattern).to_h { |entry| [ entry.key, entry.filesystem_pattern ] }
  end

  def self.github_specs
    entries.select(&:github_directory).to_h do |entry|
      [
        entry.key,
        {
          directory: entry.github_directory,
          pattern: entry.github_pattern,
          recursive: entry.github_recursive
        }
      ]
    end
  end

  def self.library_keys
    library_entries.map(&:key)
  end

  def self.library_labels
    library_entries.to_h { |entry| [ entry.key, entry.label ] }
  end

  def self.navigation_entries
    entries.select(&:navigation)
  end

  def self.dashboard_keys
    entries.select(&:dashboard).map(&:key)
  end

  def self.entries
    ENTRIES
  end

  def self.library_entries
    entries.select(&:library)
  end
end
