import { escape, addSubmit, keyboardChoice } from "arcade/exercise_helpers"

export function render(root, exercise, ctx) {
  const options = exercise.payload?.options || []
  root.innerHTML = `<p class="arena-eyebrow">Transfer · changed context</p><h2>${escape(exercise.payload?.prompt || exercise.prompt)}</h2><p class="arena-question-context">${escape(exercise.context)}</p><div class="arena-choice-list" role="radiogroup" aria-label="Transfer answer choices"></div>`
  const list = root.querySelector(".arena-choice-list")
  options.forEach((option, index) => {
    const choice = document.createElement("button")
    choice.type = "button"; choice.className = "arena-choice"; choice.dataset.arenaChoice = option.id; choice.dataset.arenaText = option.text; choice.setAttribute("aria-pressed", "false")
    choice.innerHTML = `<span class="arena-choice-key">${index + 1}</span><span>${escape(option.text)}</span>`
    choice.addEventListener("click", () => { list.querySelectorAll(".arena-choice").forEach((other) => { other.classList.remove("is-selected"); other.dataset.arenaSelected = "false"; other.setAttribute("aria-pressed", "false") }); choice.classList.add("is-selected"); choice.dataset.arenaSelected = "true"; choice.setAttribute("aria-pressed", "true") })
    list.append(choice)
  })
  addSubmit(root, ctx, "Confirm transfer")
  ctx.keyboard = (key) => keyboardChoice(root, key)
}

export function collect(root) { return { response: root.querySelector("[data-arena-selected='true']")?.dataset.arenaChoice || "" } }
