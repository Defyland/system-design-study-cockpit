class SimulationEngine
  Result = Struct.new(:input_snapshot, :output_snapshot, keyword_init: true)

  def self.call(simulation_slug:, input_snapshot:)
    new(simulation_slug, input_snapshot).call
  end

  def initialize(simulation_slug, input_snapshot)
    @simulation = SimulationCatalog.find!(simulation_slug)
    @input_snapshot = input_snapshot || {}
  end

  def call
    input = normalized_input

    Result.new(
      input_snapshot: input,
      output_snapshot: calculate(input)
    )
  end

  private

  attr_reader :simulation, :input_snapshot

  def normalized_input
    simulation.controls.to_h do |control|
      [ control.key, numeric_value_for(control) ]
    end
  end

  def numeric_value_for(control)
    value = input_snapshot[control.key] || input_snapshot[control.key.to_sym]
    number = Float(value)
    bounded_value(number.finite? ? number : control.default.to_f, control)
  rescue ArgumentError, TypeError
    control.default.to_f
  end

  def bounded_value(number, control)
    [ control.max.to_f, [ control.min.to_f, number ].max ].min
  end

  def calculate(input)
    case simulation.slug
    when "load-balancer"
      load_balancer(input)
    when "cache"
      cache(input)
    when "rate-limit-vs-load-shedding"
      rate_limit_vs_load_shedding(input)
    when "circuit-breaker"
      circuit_breaker(input)
    when "canary-rollout"
      canary_rollout(input)
    else
      {
        "decision" => "Simulador narrativo",
        "recommendedDecision" => "risky",
        "feedback" => "Explique sintoma, metrica, mitigacao e rollback."
      }
    end
  end

  def load_balancer(input)
    capacity = input.fetch("servers") * input.fetch("serverCapacity")
    utilization = capacity.positive? ? (input.fetch("requests") / capacity) * 100 : 0
    rejected = [ 0, input.fetch("requests") - capacity ].max
    error_rate = input.fetch("failureRate") + ([ 0, utilization - 100 ].max * 0.35)
    recommended_decision = if error_rate > 10 || rejected > capacity * 0.15
      "rollback"
    elsif utilization > 85
      "risky"
    else
      "safe"
    end

    {
      "utilization" => utilization,
      "rejected" => rejected,
      "errorRate" => error_rate,
      "decision" => rejected.positive? ? "Conter carga antes de adicionar features" : "Capacidade suficiente",
      "recommendedDecision" => recommended_decision,
      "feedback" => rejected.positive? ? "Primeiro eu limitaria blast radius do tenant quente; depois escalaria ou isolaria capacidade." : "Eu continuaria rollout observando utilizacao e erro upstream."
    }
  end

  def cache(input)
    origin_load = input.fetch("requests") * (1 - input.fetch("hitRate") / 100)
    origin_utilization = input.fetch("originCapacity").positive? ? (origin_load / input.fetch("originCapacity")) * 100 : 0
    staleness_risk = [ 100, input.fetch("ttl") / 12 ].min
    recommended_decision = if origin_utilization > 100
      "rollback"
    elsif origin_utilization > 85 || staleness_risk > 65
      "risky"
    else
      "safe"
    end

    {
      "originLoad" => origin_load,
      "originUtilization" => origin_utilization,
      "stalenessRisk" => staleness_risk,
      "decision" => origin_utilization > 100 ? "Cache nao protege o origin o bastante" : "Cache reduz carga, valide freshness",
      "recommendedDecision" => recommended_decision,
      "feedback" => origin_utilization > 100 ? "Eu reduziria miss storm e protegeria origin antes de aumentar TTL sem criterio." : "Eu usaria cache com TTL pequeno e invalidacao clara para nao vender dado velho."
    }
  end

  def rate_limit_vs_load_shedding(input)
    hot_tenant_load = input.fetch("requestRate") * (input.fetch("tenantShare") / 100)
    hot_tenant_excess = [ 0, hot_tenant_load - input.fetch("tenantLimit") ].max
    global_excess = [ 0, input.fetch("requestRate") - input.fetch("backendCapacity") ].max
    protected_traffic = [ 0, [ 100, ((input.fetch("requestRate") - hot_tenant_excess - global_excess) / input.fetch("requestRate")) * 100 ].min ].max
    recommended_decision = if global_excess > input.fetch("backendCapacity") * 0.2
      "rollback"
    elsif hot_tenant_excess.positive? || global_excess.positive?
      "risky"
    else
      "safe"
    end

    {
      "hotTenantExcess" => hot_tenant_excess,
      "globalExcess" => global_excess,
      "protectedTraffic" => protected_traffic,
      "decision" => global_excess.positive? ? "Shed load global e limite tenant quente" : "Rate limit por justica basta",
      "recommendedDecision" => recommended_decision,
      "feedback" => global_excess.positive? ? "Eu separaria abuso de protecao global: rate limit para fairness, load shedding para salvar capacidade." : "Eu manteria rate limit por tenant e observaria saturacao global."
    }
  end

  def circuit_breaker(input)
    amplified_load = input.fetch("requests") * (1 + (input.fetch("failureRate") / 100) * (input.fetch("retryMultiplier") - 1))
    circuit_open = input.fetch("failureRate") >= input.fetch("threshold")
    timeouts_avoided = circuit_open ? input.fetch("requests") * (input.fetch("failureRate") / 100) * input.fetch("retryMultiplier") : 0
    recommended_decision = if circuit_open && amplified_load > input.fetch("requests") * 1.2
      "rollback"
    elsif circuit_open
      "risky"
    else
      "safe"
    end

    {
      "amplifiedLoad" => amplified_load,
      "timeoutsAvoided" => timeouts_avoided,
      "circuitState" => circuit_open ? "Open" : "Closed",
      "decision" => circuit_open ? "Pausar chamadas e evitar retry storm" : "Dependencia ainda dentro do limite",
      "recommendedDecision" => recommended_decision,
      "feedback" => circuit_open ? "Eu abriria circuito, pausaria retries agressivos e preservaria o resto do checkout." : "Eu manteria observacao e nao aumentaria retry sem idempotencia."
    }
  end

  def canary_rollout(input)
    affected_users = input.fetch("users") * (input.fetch("rollout") / 100)
    error_budget_burn = input.fetch("errorRate") / 1
    latency_risk = [ 0, [ 100, ((input.fetch("latencyP95") - 300) / 900) * 100 ].min ].max
    recommended_decision = if input.fetch("errorRate") > 5 || input.fetch("latencyP95") > 900
      "rollback"
    elsif error_budget_burn > 2 || latency_risk > 50
      "risky"
    else
      "safe"
    end

    {
      "affectedUsers" => affected_users,
      "errorBudgetBurn" => error_budget_burn,
      "latencyRisk" => latency_risk,
      "decision" => recommended_decision == "rollback" ? "Rollback pelo gatilho" : "Segure canary ate estabilizar",
      "recommendedDecision" => recommended_decision,
      "feedback" => recommended_decision == "rollback" ? "Eu reverteria o path novo, manteria leitura antiga e olharia erro por coorte." : "Eu seguraria o percentual e so expandiria com erro e p95 estaveis."
    }
  end
end
