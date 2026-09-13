import { escape, addSubmit } from "arcade/exercise_helpers"

export function render(root, exercise, ctx) {
  root.innerHTML = `<p class="arena-eyebrow">Feynman · explain in your own words</p><h2>Explain the idea simply.</h2><p class="arena-question-context">Explain <strong>${escape(exercise.payload?.concept || exercise.topic)}</strong> to ${escape(exercise.payload?.explain_to || "a teammate")} under this constraint: ${escape(exercise.payload?.constraint || "one concrete boundary")}</p><label for="arena-response">My explanation: how it works and where it stops applying</label><textarea id="arena-response" class="arena-input" rows="6" autocomplete="off" required></textarea><label for="arena-self-rating">Self-rate (1–4, required)</label><select id="arena-self-rating" class="arena-input" required><option value="">Choose</option><option value="1">1 · again</option><option value="2">2 · hard</option><option value="3">3 · good</option><option value="4">4 · easy</option></select>`
  addSubmit(root, ctx, "Save explanation")
}

export function collect(root) { return { response_text: root.querySelector("#arena-response")?.value || "", self_rating: root.querySelector("#arena-self-rating")?.value || "" } }
