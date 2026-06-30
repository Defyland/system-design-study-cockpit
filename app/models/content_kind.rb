class ContentKind
  REFERENCE_DOCUMENT_GLOBS = [
    "{CASE_DRIVEN_STUDY,COURSE_OUTLINE,README,STUDY_ORDER,STUDY_PLAN}.md",
    "areas/0[1-5]-*/README.md",
    "areas/0[1-5]-*/notes.md",
    "areas/0[1-5]-*/examples/**/*.md",
    "areas/0[1-5]-*/snippets/**/*.md",
    "areas/0[6-9]-*/README.md",
    "areas/0[6-9]-*/notes.md",
    "areas/1[0-4]-*/README.md",
    "areas/1[0-4]-*/notes.md",
    "areas/10-engineering-case-studies/learning-loop.md",
    "areas/10-engineering-case-studies/sources.md",
    "assets/ementa/README.md",
    "bench/**/*.md",
    "capstones/README.md",
    "chapters/README.md",
    "decision-contrasts/README.md",
    "docs/{decisions,learning-journal}.md",
    "labs/README.md",
    "real-world-cases/ROADMAP.md",
    "reviews/{README,day-00-pre-sleep-flashcards,day-01-anchor-recall,day-03-discrimination-pass,day-07-transfer-pass,day-14-interview-compression,day-30-retention-audit}.md",
    "simulation-labs/README.md",
    "simulation-labs/sim/README.md"
  ].freeze

  REFERENCE_DOCUMENT_REGEX = %r{\A(?:
    CASE_DRIVEN_STUDY\.md|
    COURSE_OUTLINE\.md|
    README\.md|
    STUDY_ORDER\.md|
    STUDY_PLAN\.md|
    assets/ementa/README\.md|
    bench(?:/[^/]+)?/README\.md|
    capstones/README\.md|
    chapters/README\.md|
    decision-contrasts/README\.md|
    docs/(?:decisions|learning-journal)\.md|
    labs/README\.md|
    real-world-cases/ROADMAP\.md|
    reviews/(?:README|day-00-pre-sleep-flashcards|day-01-anchor-recall|day-03-discrimination-pass|day-07-transfer-pass|day-14-interview-compression|day-30-retention-audit)\.md|
    simulation-labs/README\.md|
    simulation-labs/sim/README\.md|
    areas/0[1-5]-[^/]+/(?:README\.md|notes\.md|examples/.+\.md|snippets/.+\.md)|
    areas/(?:0[6-9]|1[0-4])-[^/]+/(?:README\.md|notes\.md)|
    areas/10-engineering-case-studies/(?:learning-loop|sources)\.md
  )\z}x

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
      key: "side_track_overview",
      label: "Side Tracks"
    ),
    Entry.new(
      key: "side_track_reference",
      label: "Side Track References",
      library: true
    ),
    Entry.new(
      key: "side_track_chapter",
      label: "Side Track Chapters",
      library: true
    ),
    Entry.new(
      key: "side_track_review_card",
      label: "Side Track Review Cards",
      library: true
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
      key: "operational_playbook",
      label: "Operational Playbooks",
      short_label: "Playbooks",
      library: true,
      navigation: true,
      dashboard: true,
      filesystem_pattern: "areas/11-operational-playbooks/playbooks/*.md",
      github_directory: "areas/11-operational-playbooks/playbooks",
      github_pattern: /\A.+\.md\z/
    ),
    Entry.new(
      key: "engineering_practice",
      label: "Engineering Practice",
      short_label: "Practice",
      library: true,
      navigation: true,
      dashboard: true,
      filesystem_pattern: "areas/12-engineering-practice/cards/*.md",
      github_directory: "areas/12-engineering-practice/cards",
      github_pattern: /\A.+\.md\z/
    ),
    Entry.new(
      key: "interview_story_bank",
      label: "Interview Story Bank",
      short_label: "Interview",
      library: true,
      navigation: true,
      dashboard: true,
      filesystem_pattern: "interview/story-bank/*.md",
      github_directory: "interview/story-bank",
      github_pattern: /\A.+\.md\z/
    ),
    Entry.new(
      key: "reference_document",
      label: "Reference Docs",
      short_label: "Refs",
      library: true,
      navigation: true,
      filesystem_pattern: REFERENCE_DOCUMENT_GLOBS,
      github_directory: "",
      github_pattern: REFERENCE_DOCUMENT_REGEX,
      github_recursive: true
    ),
    Entry.new(
      key: "backend_lab",
      label: "Backend Principle Labs",
      short_label: "B Labs",
      library: true,
      dashboard: true,
      filesystem_pattern: "areas/13-backend-principle-labs/labs/*.md",
      github_directory: "areas/13-backend-principle-labs/labs",
      github_pattern: /\A.+\.md\z/
    ),
    Entry.new(
      key: "engineering_case_lab",
      label: "Engineering Case Study Labs",
      short_label: "Case Labs",
      library: true,
      dashboard: true,
      filesystem_pattern: "areas/14-engineering-case-study-labs/labs/*.md",
      github_directory: "areas/14-engineering-case-study-labs/labs",
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
