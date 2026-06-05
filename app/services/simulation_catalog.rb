class SimulationCatalog
  Simulation = Struct.new(:slug, :title, :description, :scenario, :controls, :metrics, keyword_init: true)
  Control = Struct.new(:key, :label, :min, :max, :step, :unit, :default, :hint, keyword_init: true)
  Metric = Struct.new(:key, :label, :unit, :danger_at, keyword_init: true)

  SIMULATIONS = [
    Simulation.new(
      slug: "load-balancer",
      title: "Load Balancer Capacity",
      description: "Veja quando distribuicao de carga vira saturacao, erro e decisao de rollout.",
      scenario: "Seu SaaS B2B ganhou um tenant quente. Antes de comprar maquina ou microservico, prove se o gargalo e capacidade, distribuicao ou tenant barulhento.",
      controls: [
        Control.new(key: "requests", label: "Requests/s", min: 100, max: 20_000, step: 100, unit: "rps", default: 4_500, hint: "Carga chegando no edge."),
        Control.new(key: "servers", label: "Servidores", min: 1, max: 20, step: 1, unit: "pods", default: 4, hint: "Capacidade horizontal disponivel."),
        Control.new(key: "serverCapacity", label: "Capacidade por servidor", min: 200, max: 2_000, step: 100, unit: "rps", default: 900, hint: "Nao chute infinito. Defina teto."),
        Control.new(key: "failureRate", label: "Falha upstream", min: 0, max: 30, step: 1, unit: "%", default: 2, hint: "Erro que o LB nao resolve sozinho.")
      ],
      metrics: [
        Metric.new(key: "utilization", label: "Utilizacao", unit: "%", danger_at: 85),
        Metric.new(key: "rejected", label: "Requests sem capacidade", unit: "rps", danger_at: 1),
        Metric.new(key: "errorRate", label: "Erro estimado", unit: "%", danger_at: 5),
        Metric.new(key: "decision", label: "Julgamento", unit: "", danger_at: nil)
      ]
    ),
    Simulation.new(
      slug: "cache",
      title: "Cache Hit Ratio vs Origin Protection",
      description: "Simule miss storm, TTL ruim e quando cache protege ou mascara problema.",
      scenario: "O dashboard de um produto B2B ficou lento depois de uma release. O PO quer cache. Voce precisa decidir se cache reduz carga ou cria stale data perigosa.",
      controls: [
        Control.new(key: "requests", label: "Requests/s", min: 100, max: 40_000, step: 100, unit: "rps", default: 8_000, hint: "Leituras no endpoint."),
        Control.new(key: "hitRate", label: "Hit rate", min: 0, max: 99, step: 1, unit: "%", default: 72, hint: "Quanto escapa do banco/origin."),
        Control.new(key: "originCapacity", label: "Capacidade origin", min: 100, max: 10_000, step: 100, unit: "rps", default: 2_000, hint: "Teto real antes de fila/timeout."),
        Control.new(key: "ttl", label: "TTL", min: 5, max: 3_600, step: 5, unit: "s", default: 120, hint: "Mais TTL reduz carga, mas aumenta staleness.")
      ],
      metrics: [
        Metric.new(key: "originLoad", label: "Carga no origin", unit: "rps", danger_at: 2_000),
        Metric.new(key: "originUtilization", label: "Utilizacao origin", unit: "%", danger_at: 85),
        Metric.new(key: "stalenessRisk", label: "Risco de stale", unit: "%", danger_at: 60),
        Metric.new(key: "decision", label: "Julgamento", unit: "", danger_at: nil)
      ]
    ),
    Simulation.new(
      slug: "rate-limit-vs-load-shedding",
      title: "Rate Limit vs Load Shedding",
      description: "Separe justica por cliente de protecao global do sistema.",
      scenario: "Um tenant dispara integracao agressiva ao mesmo tempo que o checkout fica perto do limite. Voce precisa decidir se limita tenant, derruba carga global ou preserva pedidos pagos.",
      controls: [
        Control.new(key: "requestRate", label: "Requests/s", min: 100, max: 50_000, step: 100, unit: "rps", default: 12_000, hint: "Carga total."),
        Control.new(key: "tenantShare", label: "Tenant quente", min: 1, max: 100, step: 1, unit: "%", default: 45, hint: "Quanto da carga vem de um ator."),
        Control.new(key: "backendCapacity", label: "Capacidade backend", min: 500, max: 30_000, step: 500, unit: "rps", default: 9_000, hint: "Protecao global."),
        Control.new(key: "tenantLimit", label: "Limite por tenant", min: 100, max: 20_000, step: 100, unit: "rps", default: 2_500, hint: "Justica local.")
      ],
      metrics: [
        Metric.new(key: "hotTenantExcess", label: "Excesso do tenant", unit: "rps", danger_at: 1),
        Metric.new(key: "globalExcess", label: "Excesso global", unit: "rps", danger_at: 1),
        Metric.new(key: "protectedTraffic", label: "Trafego protegido", unit: "%", danger_at: nil),
        Metric.new(key: "decision", label: "Julgamento", unit: "", danger_at: nil)
      ]
    ),
    Simulation.new(
      slug: "circuit-breaker",
      title: "Circuit Breaker Under PSP Timeout",
      description: "Teste quando retry piora uma dependencia doente e quando abrir circuito preserva o resto.",
      scenario: "O PSP esta respondendo lento. Produto quer continuar tentando. Voce precisa limitar blast radius sem perder a trilha de pagamento.",
      controls: [
        Control.new(key: "requests", label: "Tentativas/min", min: 100, max: 30_000, step: 100, unit: "req/min", default: 6_000, hint: "Chamadas para a dependencia."),
        Control.new(key: "failureRate", label: "Falhas", min: 0, max: 100, step: 1, unit: "%", default: 18, hint: "Timeout/erro do PSP."),
        Control.new(key: "threshold", label: "Threshold", min: 1, max: 80, step: 1, unit: "%", default: 12, hint: "Quando o circuito abre."),
        Control.new(key: "retryMultiplier", label: "Multiplicador de retry", min: 1, max: 5, step: 0.5, unit: "x", default: 2, hint: "Retry sem criterio vira ataque.")
      ],
      metrics: [
        Metric.new(key: "amplifiedLoad", label: "Carga amplificada", unit: "req/min", danger_at: 8_000),
        Metric.new(key: "timeoutsAvoided", label: "Timeouts evitados", unit: "req/min", danger_at: nil),
        Metric.new(key: "circuitState", label: "Estado", unit: "", danger_at: nil),
        Metric.new(key: "decision", label: "Julgamento", unit: "", danger_at: nil)
      ]
    ),
    Simulation.new(
      slug: "canary-rollout",
      title: "Canary Rollout and Rollback Trigger",
      description: "Pratique rollout gradual com gatilho concreto de rollback.",
      scenario: "Voce mudou o read path de pedidos para usar replica/cache. A release parece pequena, mas pode degradar checkout e atendimento.",
      controls: [
        Control.new(key: "users", label: "Usuarios afetados", min: 100, max: 1_000_000, step: 100, unit: "users", default: 120_000, hint: "Tamanho da base exposta."),
        Control.new(key: "rollout", label: "Canary", min: 1, max: 100, step: 1, unit: "%", default: 5, hint: "Percentual no novo caminho."),
        Control.new(key: "errorRate", label: "Erro no canary", min: 0, max: 20, step: 0.1, unit: "%", default: 1.8, hint: "Erro observado."),
        Control.new(key: "latencyP95", label: "Latencia p95", min: 50, max: 3_000, step: 10, unit: "ms", default: 420, hint: "Sinal de degradacao antes do erro.")
      ],
      metrics: [
        Metric.new(key: "affectedUsers", label: "Usuarios no risco", unit: "", danger_at: 10_000),
        Metric.new(key: "errorBudgetBurn", label: "Burn estimado", unit: "x", danger_at: 2),
        Metric.new(key: "latencyRisk", label: "Risco latencia", unit: "%", danger_at: 70),
        Metric.new(key: "decision", label: "Julgamento", unit: "", danger_at: nil)
      ]
    )
  ].freeze

  def self.all
    SIMULATIONS
  end

  def self.find(slug)
    all.detect { |simulation| simulation.slug == slug }
  end

  def self.find!(slug)
    find(slug) || raise(ActiveRecord::RecordNotFound, "Simulation not found: #{slug}")
  end
end
