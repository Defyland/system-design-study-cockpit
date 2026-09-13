import { escape, addSubmit, learningMarkup } from "arcade/exercise_helpers"

export function render(root, exercise, ctx) {
  root.innerHTML = `<p class="arena-eyebrow">Meet · understand the decision</p><h2>${escape(exercise.prompt)}</h2><p class="arena-question-context">${escape(exercise.context)}</p><section class="arena-model-card" aria-label="Model phrasing"><p class="arena-eyebrow">Model phrasing</p><p>${escape(exercise.payload?.model_text || "The model appears for the active Meet card.")}</p></section><p class="arena-instruction">Read the answer in first person and identify the fact or decision it explains. When a choice is involved, consider its reason, cost, and the condition that would change it. Turn anything unclear into a specific question.</p>`
  root.insertAdjacentHTML("beforeend", learningMarkup(exercise.payload?.learning))
  addSubmit(root, ctx, "Got it")
}

export function collect() { return { response: { confirmed: true } } }
