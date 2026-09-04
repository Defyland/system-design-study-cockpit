import { escape, addSubmit } from "arcade/exercise_helpers"

export function render(root, exercise, ctx) {
  const model = exercise.payload?.model_text || ""
  root.innerHTML = `<p class="arena-eyebrow">Speak · shadow or transcribe</p><h2>${escape(exercise.prompt)}</h2><p class="arena-question-context">${escape(exercise.context)}</p><p class="arena-instruction">Listen to the exact model and repeat aloud. A transcript is optional; if you leave it blank, self-rating is capped at good. This Arena uses browser speech synthesis only; Apple Speech and Realtime are not connected here.</p><textarea id="arena-response" class="arena-input" rows="5" autocomplete="off" placeholder="Optional transcript — leave blank to self-rate shadowing"></textarea><label for="arena-self-rating">Self-rate (1–4)</label><select id="arena-self-rating" class="arena-input"><option value="">Choose</option><option value="1">1 · again</option><option value="2">2 · hard</option><option value="3">3 · good</option><option value="4">4 · easy</option></select>`
  const listen = document.createElement("button"); listen.type = "button"; listen.className = "arena-button arena-button-secondary"; listen.textContent = "Listen to model"; listen.addEventListener("click", () => { if (window.speechSynthesis && model) window.speechSynthesis.speak(new SpeechSynthesisUtterance(model)) }); root.querySelector(".arena-instruction").after(listen)
  addSubmit(root, ctx, "Save speaking pass")
}

export function collect(root) { return { response_text: root.querySelector("#arena-response")?.value || "", self_rating: root.querySelector("#arena-self-rating")?.value || "" } }
