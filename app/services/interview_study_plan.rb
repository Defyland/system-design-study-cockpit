class InterviewStudyPlan
  Day = Struct.new(:index, :label, :focus, :objective, :documents, :checkpoints, keyword_init: true)
  Plan = Struct.new(:days, keyword_init: true)

  DOCUMENTS = [
    {
      focus: "DSA operating system",
      objective: "Travar o loop de entrevista antes do codigo.",
      refs: [
        { kind: "side_track_chapter", slug: "backend-interview-foundations-01-dsa-operating-system-and-pattern-selection" },
        { kind: "side_track_review_card", slug: "backend-interview-foundations-01-dsa-operating-system-and-pattern-selection" },
        { kind: "reference_document", source_path: "areas/01-metodo-e-entrevistas/snippets/system-design-interview-checklist.md" }
      ]
    },
    {
      focus: "DSA core patterns",
      objective: "Fechar HashMap, sliding window, BFS/DFS e DP com follow-up.",
      refs: [
        { kind: "side_track_chapter", slug: "backend-interview-foundations-02-dsa-core-problems-in-ruby-and-typescript" },
        { kind: "side_track_review_card", slug: "backend-interview-foundations-02-dsa-core-problems-in-ruby-and-typescript" },
        { kind: "side_track_reference", slug: "backend-interview-foundations-source-map" }
      ]
    },
    {
      focus: "DSA execution in TypeScript",
      objective: "Fixar traps de runtime e fila/ordenacao em TypeScript.",
      refs: [
        { kind: "side_track_chapter", slug: "backend-interview-foundations-02-dsa-core-problems-in-ruby-and-typescript" },
        { kind: "side_track_reference", slug: "backend-interview-foundations-source-map" },
        { kind: "reference_document", source_path: "areas/01-metodo-e-entrevistas/snippets/senior-production-answer-template.md" }
      ]
    },
    {
      focus: "System design delivery",
      objective: "Conduzir requisito, estimativa e trade-off sem vender stack cedo demais.",
      refs: [
        { kind: "side_track_chapter", slug: "backend-interview-foundations-03-system-design-delivery-framework" },
        { kind: "side_track_review_card", slug: "backend-interview-foundations-03-system-design-delivery-framework" }
      ]
    },
    {
      focus: "System design canonical pack",
      objective: "Rodar URL shortener, rate limiter, feed e queue como families.",
      refs: [
        { kind: "side_track_chapter", slug: "backend-interview-foundations-04-system-design-canonical-problems" },
        { kind: "side_track_review_card", slug: "backend-interview-foundations-04-system-design-canonical-problems" },
        { kind: "reference_document", source_path: "areas/01-metodo-e-entrevistas/examples/interview-walkthrough-marketplace-search.md" }
      ]
    },
    {
      focus: "Rails interview surface",
      objective: "Responder N+1, transacao, locking, jobs e cache com precisao.",
      refs: [
        { kind: "side_track_chapter", slug: "backend-interview-foundations-05-ruby-on-rails-interview-surface-area" },
        { kind: "side_track_review_card", slug: "backend-interview-foundations-05-ruby-on-rails-interview-surface-area" },
        { kind: "interview_story_bank", slug: "03-ruby-rails-senior-question-bank" }
      ]
    },
    {
      focus: "Rails production voice",
      objective: "Conectar resposta de stack a casos reais e narrativas STAR.",
      refs: [
        { kind: "interview_story_bank", slug: "01-ruby-rails-backend-story-bank" },
        { kind: "reference_document", source_path: "areas/01-metodo-e-entrevistas/examples/interview-walkthrough-checkout-incident.md" }
      ]
    },
    {
      focus: "JavaScript and TypeScript interview surface",
      objective: "Dominar Map, Set, sort, unions e event loop sem resposta vaga.",
      refs: [
        { kind: "side_track_chapter", slug: "backend-interview-foundations-06-javascript-and-typescript-interview-surface-area" },
        { kind: "side_track_review_card", slug: "backend-interview-foundations-06-javascript-and-typescript-interview-surface-area" }
      ]
    },
    {
      focus: "Search and retrieval conversations",
      objective: "Praticar a ponte entre system design e permission-aware retrieval.",
      refs: [
        { kind: "chapter", slug: "chapter-09-search-indexing-and-permission-aware-retrieval" },
        { kind: "review_card", slug: "09-search-indexing-and-permission-aware-retrieval" },
        { kind: "real_world_case", slug: "dropbox-nautilus-search" }
      ]
    },
    {
      focus: "Rate limit, auth and edge boundaries",
      objective: "Treinar pergunta lateral que mistura API, segurança e escala.",
      refs: [
        { kind: "chapter", slug: "chapter-06-edge-rate-limiting-waf-and-gateway-boundaries" },
        { kind: "backend_principle", slug: "rate-limiting-algorithms-and-keys" },
        { kind: "backend_lab", slug: "build-a-ruby-rate-limiter" }
      ]
    },
    {
      focus: "Idempotency and ambiguous failure",
      objective: "Fechar uma resposta forte para write path critico.",
      refs: [
        { kind: "chapter", slug: "chapter-03-idempotent-writes-under-ambiguous-failure" },
        { kind: "backend_lab", slug: "build-an-idempotent-write-api" },
        { kind: "real_world_case", slug: "stripe-idempotent-payments" }
      ]
    },
    {
      focus: "Data and transactions",
      objective: "Fixar consulta, indice, replica e lock com criterio.",
      refs: [
        { kind: "chapter", slug: "chapter-01-relational-scaling-and-operational-discipline" },
        { kind: "backend_lab", slug: "tune-postgres-indexes-and-transactions" },
        { kind: "real_world_case", slug: "github-rails-and-mysql-at-scale" }
      ]
    },
    {
      focus: "Mock loop and compression",
      objective: "Misturar DSA, Rails e system design em tempo limitado.",
      refs: [
        { kind: "reference_document", source_path: "reviews/day-14-interview-compression.md" },
        { kind: "reference_document", source_path: "reviews/day-07-transfer-pass.md" },
        { kind: "decision_contrast", slug: "11-fanout-on-write-vs-fanout-on-read" }
      ]
    },
    {
      focus: "Final rehearsal",
      objective: "Rodar revisão curta, drills e story bank antes da entrevista.",
      refs: [
        { kind: "reference_document", source_path: "reviews/day-30-retention-audit.md" },
        { kind: "interview_story_bank", slug: "04-backend-voice-call-narrative" },
        { kind: "side_track_overview", slug: "backend-interview-foundations" }
      ]
    }
  ].freeze

  def call
    documents_by_ref = indexed_documents

    days = DOCUMENTS.each_with_index.map do |entry, index|
      documents = entry.fetch(:refs).filter_map { |ref| documents_by_ref[lookup_key(ref)] }

      Day.new(
        index: index + 1,
        label: "Dia %02d" % (index + 1),
        focus: entry.fetch(:focus),
        objective: entry.fetch(:objective),
        documents: documents,
        checkpoints: checkpoint_prompts_for(documents)
      )
    end

    Plan.new(days: days)
  end

  private

  def indexed_documents
    @indexed_documents ||= load_documents.each_with_object({}) do |document, index|
      index[[ document.kind, :slug, document.slug ]] = document
      index[[ document.kind, :source_path, document.source_path ]] = document
    end
  end

  def load_documents
    refs = DOCUMENTS.flat_map { |entry| entry.fetch(:refs) }.uniq
    kinds = refs.map { |ref| ref.fetch(:kind) }.uniq
    slugs = refs.filter_map { |ref| ref[:slug] }
    source_paths = refs.filter_map { |ref| ref[:source_path] }
    scopes = []
    base_scope = StudyDocument.where(kind: kinds)

    scopes << base_scope.where(slug: slugs) if slugs.any?
    scopes << base_scope.where(source_path: source_paths) if source_paths.any?

    return [] if scopes.empty?

    scopes.reduce { |combined_scope, scope| combined_scope.or(scope) }.includes(:checkpoints).to_a
  end

  def lookup_key(ref)
    attribute = ref[:slug] ? :slug : :source_path
    [ ref.fetch(:kind), attribute, ref.fetch(attribute) ]
  end

  def checkpoint_prompts_for(documents)
    documents.flat_map { |document| document.checkpoints.first(2).map(&:prompt) }.compact.uniq.first(5)
  end
end
