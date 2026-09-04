import { escape, addSubmit, keyboardChoice } from "arcade/exercise_helpers"

export function render(root, exercise, ctx) {
  root.innerHTML = `<p class="arena-eyebrow">Spot the trap · name the axis</p><h2>What makes this phrasing weaker?</h2><p class="arena-question-context">${escape(exercise.payload?.distractor || exercise.prompt)}</p><div class="arena-choice-list" role="radiogroup" aria-label="Language axes"></div>`
  const list = root.querySelector(".arena-choice-list")
  ;(exercise.payload?.axes || []).forEach((axis, index) => {
    const choice = document.createElement("button")
    choice.type = "button"; choice.className = "arena-choice"; choice.dataset.arenaChoice = axis; choice.dataset.arenaText = axis; choice.setAttribute("aria-pressed", "false")
    choice.innerHTML = `<span class="arena-choice-key">${index + 1}</span><span>${escape(axis)}</span>`
    choice.addEventListener("click", () => { list.querySelectorAll(".arena-choice").forEach((other) => { other.classList.remove("is-selected"); other.dataset.arenaSelected = "false"; other.setAttribute("aria-pressed", "false") }); choice.classList.add("is-selected"); choice.dataset.arenaSelected = "true"; choice.setAttribute("aria-pressed", "true") })
    list.append(choice)
  })
  addSubmit(root, ctx)
  ctx.keyboard = (key) => keyboardChoice(root, key)
}

export function collect(root) { return { response: root.querySelector("[data-arena-selected='true']")?.dataset.arenaChoice || "" } }
