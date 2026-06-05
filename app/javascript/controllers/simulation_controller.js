import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "value", "metric", "inputSnapshot", "decision", "feedback"]
  static values = { slug: String }

  connect() {
    this.manualDecision = false
    this.recalculate()
  }

  choose() {
    this.manualDecision = true
  }

  recalculate() {
    const input = this.inputValues()
    const output = this.calculate(input)

    this.valueTargets.forEach((target) => {
      const value = input[target.dataset.key]
      target.textContent = this.format(value)
    })

    this.metricTargets.forEach((target) => {
      const value = output[target.dataset.key]
      target.textContent = this.format(value)
      this.markDanger(target, value)
    })

    this.inputSnapshotTarget.value = JSON.stringify(input)
    this.applyRecommendedDecision(output.recommendedDecision)
    this.applyFeedback(output.feedback)
  }

  inputValues() {
    return this.inputTargets.reduce((values, input) => {
      values[input.dataset.key] = Number.parseFloat(input.value)
      return values
    }, {})
  }

  calculate(input) {
    switch (this.slugValue) {
      case "load-balancer":
        return this.loadBalancer(input)
      case "cache":
        return this.cache(input)
      case "rate-limit-vs-load-shedding":
        return this.rateLimitVsLoadShedding(input)
      case "circuit-breaker":
        return this.circuitBreaker(input)
      case "canary-rollout":
        return this.canaryRollout(input)
      default:
        return { decision: "Simulador narrativo", recommendedDecision: "risky", feedback: "Explique sintoma, metrica, mitigacao e rollback." }
    }
  }

  loadBalancer(input) {
    const capacity = input.servers * input.serverCapacity
    const utilization = (input.requests / capacity) * 100
    const rejected = Math.max(0, input.requests - capacity)
    const errorRate = input.failureRate + Math.max(0, utilization - 100) * 0.35
    const recommendedDecision = errorRate > 10 || rejected > capacity * 0.15 ? "rollback" : utilization > 85 ? "risky" : "safe"

    return {
      utilization,
      rejected,
      errorRate,
      decision: rejected > 0 ? "Conter carga antes de adicionar features" : "Capacidade suficiente",
      recommendedDecision,
      feedback: rejected > 0 ? "Primeiro eu limitaria blast radius do tenant quente; depois escalaria ou isolaria capacidade." : "Eu continuaria rollout observando utilizacao e erro upstream."
    }
  }

  cache(input) {
    const originLoad = input.requests * (1 - input.hitRate / 100)
    const originUtilization = (originLoad / input.originCapacity) * 100
    const stalenessRisk = Math.min(100, input.ttl / 12)
    const recommendedDecision = originUtilization > 100 ? "rollback" : originUtilization > 85 || stalenessRisk > 65 ? "risky" : "safe"

    return {
      originLoad,
      originUtilization,
      stalenessRisk,
      decision: originUtilization > 100 ? "Cache nao protege o origin o bastante" : "Cache reduz carga, valide freshness",
      recommendedDecision,
      feedback: originUtilization > 100 ? "Eu reduziria miss storm e protegeria origin antes de aumentar TTL sem criterio." : "Eu usaria cache com TTL pequeno e invalidacao clara para nao vender dado velho."
    }
  }

  rateLimitVsLoadShedding(input) {
    const hotTenantLoad = input.requestRate * (input.tenantShare / 100)
    const hotTenantExcess = Math.max(0, hotTenantLoad - input.tenantLimit)
    const globalExcess = Math.max(0, input.requestRate - input.backendCapacity)
    const protectedTraffic = Math.max(0, Math.min(100, ((input.requestRate - hotTenantExcess - globalExcess) / input.requestRate) * 100))
    const recommendedDecision = globalExcess > input.backendCapacity * 0.2 ? "rollback" : hotTenantExcess > 0 || globalExcess > 0 ? "risky" : "safe"

    return {
      hotTenantExcess,
      globalExcess,
      protectedTraffic,
      decision: globalExcess > 0 ? "Shed load global e limite tenant quente" : "Rate limit por justica basta",
      recommendedDecision,
      feedback: globalExcess > 0 ? "Eu separaria abuso de protecao global: rate limit para fairness, load shedding para salvar capacidade." : "Eu manteria rate limit por tenant e observaria saturacao global."
    }
  }

  circuitBreaker(input) {
    const amplifiedLoad = input.requests * (1 + (input.failureRate / 100) * (input.retryMultiplier - 1))
    const circuitOpen = input.failureRate >= input.threshold
    const timeoutsAvoided = circuitOpen ? input.requests * (input.failureRate / 100) * input.retryMultiplier : 0
    const recommendedDecision = circuitOpen && amplifiedLoad > input.requests * 1.2 ? "rollback" : circuitOpen ? "risky" : "safe"

    return {
      amplifiedLoad,
      timeoutsAvoided,
      circuitState: circuitOpen ? "Open" : "Closed",
      decision: circuitOpen ? "Pausar chamadas e evitar retry storm" : "Dependencia ainda dentro do limite",
      recommendedDecision,
      feedback: circuitOpen ? "Eu abriria circuito, pausaria retries agressivos e preservaria o resto do checkout." : "Eu manteria observacao e nao aumentaria retry sem idempotencia."
    }
  }

  canaryRollout(input) {
    const affectedUsers = input.users * (input.rollout / 100)
    const errorBudgetBurn = input.errorRate / 1
    const latencyRisk = Math.max(0, Math.min(100, ((input.latencyP95 - 300) / 900) * 100))
    const recommendedDecision = input.errorRate > 5 || input.latencyP95 > 900 ? "rollback" : errorBudgetBurn > 2 || latencyRisk > 50 ? "risky" : "safe"

    return {
      affectedUsers,
      errorBudgetBurn,
      latencyRisk,
      decision: recommendedDecision === "rollback" ? "Rollback pelo gatilho" : "Segure canary ate estabilizar",
      recommendedDecision,
      feedback: recommendedDecision === "rollback" ? "Eu reverteria o path novo, manteria leitura antiga e olharia erro por coorte." : "Eu seguraria o percentual e so expandiria com erro e p95 estaveis."
    }
  }

  markDanger(target, value) {
    const card = target.closest(".metric-card")
    const dangerAt = Number.parseFloat(card.dataset.dangerAt)
    card.classList.toggle("danger", Number.isFinite(dangerAt) && Number.parseFloat(value) >= dangerAt)
  }

  applyRecommendedDecision(decision) {
    if (this.manualDecision || !decision) return

    const target = this.decisionTargets.find((radio) => radio.value === decision)
    if (target) target.checked = true
  }

  applyFeedback(feedback) {
    if (!this.hasFeedbackTarget || this.feedbackTarget.value.trim().length > 0) return

    this.feedbackTarget.value = feedback || ""
  }

  format(value) {
    if (typeof value === "string") return value
    if (!Number.isFinite(value)) return "--"
    if (Math.abs(value) >= 1000) return Math.round(value).toLocaleString("pt-BR")
    if (value % 1 === 0) return value.toString()

    return value.toFixed(1)
  }
}
