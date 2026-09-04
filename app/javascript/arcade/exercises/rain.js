import { escape, addSubmit, keyboardChoice } from "arcade/exercise_helpers"

// Rain keeps recognition deterministic while making the timed round feel
// different from the regular choice card. The server still grades the same
// choose_best payload; animation is only presentation and is disabled by the
// global reduced-motion rule.
export function render(root, exercise, ctx) {
  const options = exercise.payload?.options || []
  const deadline = Number(exercise.payload?.time_limit_ms || 15_000)
  root.innerHTML = `<div class="arena-rain" data-game-state="running" data-game-deadline-ms="${deadline}" data-game-lanes="4"><p class="arena-eyebrow">Rain · timed recognition</p><h2>${escape(exercise.prompt)}</h2><p class="arena-question-context">${escape(exercise.context)}</p><div class="arena-rain-lanes" role="radiogroup" aria-label="Falling answer choices"></div><p class="arena-instruction arena-rain-clock" data-arena-rain-clock>${Math.ceil(deadline / 1000)} seconds</p></div>`
  const lanes = root.querySelector(".arena-rain-lanes")
  options.forEach((option, index) => {
    const choice = document.createElement("button")
    choice.type = "button"
    choice.className = "arena-choice arena-rain-choice"
    choice.dataset.arenaChoice = option.id
    choice.dataset.arenaText = option.text
    choice.dataset.arenaLane = String(index % 4)
    choice.setAttribute("aria-pressed", "false")
    choice.style.setProperty("--duration", `${Math.max(5, 9 - index * 0.45)}s`)
    choice.style.setProperty("--delay", `${index * 0.55}s`)
    choice.style.setProperty("--travel", `${110 + (index % 2) * 18}%`)
    choice.innerHTML = `<span class="arena-choice-key">${index + 1}</span><span>${escape(option.text)}</span>`
    choice.addEventListener("click", () => {
      lanes.querySelectorAll(".arena-choice").forEach((other) => {
        other.classList.remove("is-selected")
        other.dataset.arenaSelected = "false"
        other.setAttribute("aria-pressed", "false")
      })
      choice.classList.add("is-selected")
      choice.dataset.arenaSelected = "true"
      choice.setAttribute("aria-pressed", "true")
    })
    lanes.append(choice)
  })
  addSubmit(root, ctx, "Lock answer")
  ctx.keyboard = (key) => keyboardChoice(root, key)
  const clock = root.querySelector("[data-arena-rain-clock]")
  let remaining = deadline
  const timer = window.setInterval(() => {
    remaining -= 250
    if (clock) clock.textContent = `${Math.max(0, Math.ceil(remaining / 1000))} seconds`
    if (remaining <= 0) {
      window.clearInterval(timer)
      root.querySelector(".arena-rain")?.setAttribute("data-game-state", "timeout")
      ctx.submit()
    }
  }, 250)
  ctx.cleanup = [...(ctx.cleanup || []), () => window.clearInterval(timer)]
}

export function collect(root) {
  return { response: root.querySelector("[data-arena-selected='true']")?.dataset.arenaChoice || "" }
}
