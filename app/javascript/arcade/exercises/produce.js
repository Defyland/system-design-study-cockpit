import { escape, addSubmit } from "arcade/exercise_helpers"

export function render(root, exercise, ctx) {
  root.innerHTML = `<p class="arena-eyebrow">Produce · recall without the model</p><h2>${escape(exercise.prompt)}</h2><p class="arena-question-context">${escape(exercise.context)}</p><p class="arena-instruction">Cue: ${escape(exercise.payload?.cue || "State the decision and the evidence.")}</p><label for="arena-response">Your answer</label><textarea id="arena-response" class="arena-input" rows="6" autocomplete="off"></textarea><label for="arena-self-rating">Self-rate your recall (1–4)</label><select id="arena-self-rating" class="arena-input"><option value="">Choose</option><option value="1">1 · again</option><option value="2">2 · hard</option><option value="3">3 · good</option><option value="4">4 · easy</option></select>`
  addSubmit(root, ctx, "Submit production")
}

export function collect(root) { return { response_text: root.querySelector("#arena-response")?.value || "", self_rating: root.querySelector("#arena-self-rating")?.value || "" } }
