import { escape, addSubmit } from "arcade/exercise_helpers"

export function render(root, exercise, ctx) {
  root.innerHTML = `<p class="arena-eyebrow">Meet · read once</p><h2>${escape(exercise.prompt)}</h2><p class="arena-question-context">${escape(exercise.context)}</p><section class="arena-model-card" aria-label="Model phrasing"><p class="arena-eyebrow">Model phrasing</p><p>${escape(exercise.payload?.model_text || "The model appears for the active Meet card.")}</p></section><p class="arena-instruction">Read the situation, then ask yourself what a precise answer makes explicit.</p>`
  addSubmit(root, ctx, "Got it")
}

export function collect() { return { response: { confirmed: true } } }
